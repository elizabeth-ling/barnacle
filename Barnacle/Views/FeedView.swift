import SwiftUI
import SwiftData
import AppKit
import OSLog

/// The main dashboard (spec `02`): internships from tracked companies, newest-first by effective
/// date, filtered by company, click-to-open. Every pixel of chrome comes from spec `06`.
struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(NotificationService.self) private var notifications

    /// `effectiveDate` is computed, so SwiftData can't sort on it — this query gives a stable
    /// order and `visiblePostings` does the real sort in memory. The list is small (one user's
    /// hand-picked companies), so the cost is nil and the reactivity is the point: postings the
    /// background scrape inserts land here with no reload.
    @Query(sort: \JobPosting.dateFirstSeen, order: .reverse)
    private var postings: [JobPosting]

    @Query(sort: \Company.name)
    private var companies: [Company]

    @AppStorage(FeedSortOrder.storageKey) private var storedSortOrder = FeedSortOrder.newest.rawValue

    /// Not persisted: the spec only asks for the sort choice to survive a restart.
    @State private var companyFilter: UUID?

    /// Swaps the list between the ordinary feed and the postings the user has dismissed.
    /// Deliberately not persisted — the feed should always open as the feed, never leave the
    /// user parked in a view of things they have already ruled out.
    @State private var showDismissed = false

    /// The posting the undo banner is offering to put back. Cleared on a timer, or as soon as
    /// the user acts.
    @State private var undoTarget: JobPosting?

    @State private var isAddingCompany = false
    @State private var isManagingCompanies = false

    /// Set when the user clicks a notification (spec `04`): the feed narrows to that batch so
    /// the postings the notification was about are the only thing on screen. Nil the rest of
    /// the time, which is the normal feed.
    @State private var revealedPostingIDs: Set<UUID>?

    private var sortOrder: FeedSortOrder {
        FeedSortOrder(rawValue: storedSortOrder) ?? .newest
    }

    private var sortOrderBinding: Binding<FeedSortOrder> {
        Binding(get: { sortOrder }, set: { storedSortOrder = $0.rawValue })
    }

    /// A company can now be removed while its filter is active (spec `03`). The filter control
    /// falls back to "All companies" when it can't name the selection, so the list has to agree
    /// — otherwise the feed stays filtered to a company nothing on screen mentions.
    private var activeCompanyFilter: UUID? {
        guard let companyFilter, companies.contains(where: { $0.id == companyFilter }) else { return nil }
        return companyFilter
    }

    private var dismissedCount: Int {
        postings.lazy.filter(\.isDismissed).count
    }

    private var visiblePostings: [JobPosting] {
        postings
            .filter { posting in
                // Dismissal outranks everything else: the two lists never mix, and a reveal
                // can't drag a dismissed posting back into the feed.
                guard posting.isDismissed == showDismissed else { return false }
                // A notification reveal replaces the company filter rather than combining with
                // it — the point is to show that exact batch, whatever companies it spans.
                if let revealedPostingIDs { return revealedPostingIDs.contains(posting.id) }
                return activeCompanyFilter == nil || posting.companyID == activeCompanyFilter
            }
            .sorted { lhs, rhs in
                switch sortOrder {
                case .newest: lhs.effectiveDate > rhs.effectiveDate
                case .oldest: lhs.effectiveDate < rhs.effectiveDate
                }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Feed") {
                HStack(spacing: 6) {
                    CompanyFilterControl(
                        companies: companies,
                        selection: $companyFilter,
                        onManageCompanies: { isManagingCompanies = true }
                    )
                    if dismissedCount > 0 {
                        Button("Dismissed (\(dismissedCount))") {
                            showDismissed.toggle()
                        }
                        .buttonStyle(.quietControl(isActive: showDismissed))
                        .help(showDismissed ? "Back to the feed" : "Show dismissed postings")
                    }
                    FeedSortToggle(selection: sortOrderBinding)
                    FeedRefreshControl()
                    HeaderAddButton(help: "Add a company") { isAddingCompany = true }
                }
            }

            // Spec `01` records per-company failures but nothing read them, so a company whose
            // board has moved looked identical to one with no open internships.
            if let failures = scrapeCoordinator.lastRun?.failures, !failures.isEmpty {
                ScrapeFailureBanner(failures: failures) { isManagingCompanies = true }
            }

            if revealedPostingIDs != nil {
                revealBanner
            }

            if let undoTarget {
                undoBanner(for: undoTarget)
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .sheet(isPresented: $isAddingCompany) {
            AddCompanyView()
        }
        .sheet(isPresented: $isManagingCompanies) {
            ManageCompaniesView()
        }
        // Both paths matter: `.task` catches a notification clicked while Barnacle was closed
        // (the reveal is already waiting by the time the Feed first appears), `.onChange` catches
        // one clicked while it was open.
        .task { applyPendingReveal() }
        .onChange(of: notifications.pendingFeedReveal) { _, _ in applyPendingReveal() }
        // The reveal overrides the company filter, so touching the filter has to dismiss it —
        // otherwise picking a company would silently do nothing.
        .onChange(of: companyFilter) { _, _ in revealedPostingIDs = nil }
        // Switching lists is its own act of navigation: a reveal narrowed to one notification's
        // batch would otherwise still be filtering the dismissed list.
        .onChange(of: showDismissed) { _, _ in
            revealedPostingIDs = nil
            undoTarget = nil
        }
        // Restoring the last dismissed posting empties this list and takes its control off the
        // header, so put the user back on the feed rather than in a dead end.
        .onChange(of: dismissedCount) { _, count in
            if count == 0 { showDismissed = false }
        }
        // The undo offer is transient — six seconds is long enough to catch a misclick, and the
        // Dismissed view is the durable way back after that.
        .task(id: undoTarget?.id) {
            guard let target = undoTarget else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, undoTarget?.id == target.id else { return }
            undoTarget = nil
        }
    }

    /// Says why the feed is showing a subset, and gets the user back out of it.
    private var revealBanner: some View {
        HStack(spacing: 8) {
            Text(revealBannerText)
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.textSecondary)

            Spacer(minLength: 8)

            Button("Show all") {
                revealedPostingIDs = nil
                companyFilter = nil
            }
            .buttonStyle(.quietControl())
        }
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .padding(.vertical, 6)
        .background(Theme.Palette.accentTint)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var revealBannerText: String {
        let count = visiblePostings.count
        return count == 1 ? "Showing 1 new internship" : "Showing \(count) new internships"
    }

    /// The one chance to take a dismissal back without going looking for it.
    private func undoBanner(for posting: JobPosting) -> some View {
        HStack(spacing: 8) {
            Text("Dismissed \u{201C}\(posting.title)\u{201D}")
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Undo") {
                setDismissed(false, on: posting)
            }
            .buttonStyle(.quietControl())
        }
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .padding(.vertical, 6)
        .background(Theme.Palette.surfaceAlt)
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder
    private var content: some View {
        if companies.isEmpty && postings.isEmpty {
            EmptyState(
                title: "No companies yet",
                message: "Add a company with the + button to start tracking internships.",
                systemImage: "tray"
            )
        } else if postings.isEmpty && scrapeCoordinator.isScraping {
            // First scrape in flight: a quiet inline spinner, never a blocking modal.
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for internships\u{2026}")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if postings.isEmpty {
            EmptyState(
                title: "No internships found yet",
                message: "We check every 15 minutes.",
                systemImage: "clock"
            ) {
                Button("Refresh now") {
                    Task { await scrapeCoordinator.refreshNow() }
                }
                .buttonStyle(.barnacleSecondary)
                .disabled(scrapeCoordinator.isScraping)
            }
        } else if showDismissed && visiblePostings.isEmpty {
            EmptyState(
                title: "Nothing dismissed here",
                message: "Dismissed postings from other companies are still listed under \u{201C}All companies.\u{201D}",
                systemImage: "eye.slash"
            ) {
                Button("Back to the feed") { showDismissed = false }
                    .buttonStyle(.barnacleSecondary)
            }
        } else if visiblePostings.isEmpty && activeCompanyFilter == nil && revealedPostingIDs == nil {
            // Everything stored has been dismissed. Without this branch the feed would claim
            // nothing came from a company the user never filtered to.
            EmptyState(
                title: "You\u{2019}ve dismissed everything",
                message: "New postings will show up here as they\u{2019}re found.",
                systemImage: "checkmark.circle"
            ) {
                Button("Show dismissed") { showDismissed = true }
                    .buttonStyle(.barnacleSecondary)
            }
        } else if visiblePostings.isEmpty {
            EmptyState(
                title: revealedPostingIDs == nil ? "Nothing from this company yet" : "Those postings are gone",
                message: revealedPostingIDs == nil
                    ? "Switch back to all companies to see the rest of the feed."
                    : "They were removed along with their company. The rest of the feed is still here.",
                systemImage: "line.3.horizontal.decrease"
            ) {
                Button("All companies") {
                    companyFilter = nil
                    revealedPostingIDs = nil
                }
                .buttonStyle(.barnacleSecondary)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visiblePostings) { posting in
                        PostingRow(
                            posting: posting,
                            onOpen: { open(posting) },
                            onSetDismissed: { setDismissed($0, on: posting) }
                        )
                        Hairline()
                    }
                }
            }
        }
    }

    /// Narrows the feed to the postings a clicked notification was about (spec `04`).
    ///
    /// Ids that no longer resolve are dropped — a company can be removed, postings and all,
    /// between the notification and the click — and a reveal that resolves to nothing is
    /// ignored, so the click still brings the app forward but leaves the feed as it was.
    private func applyPendingReveal() {
        guard let request = notifications.takePendingFeedReveal() else { return }

        let stored = Set(postings.map(\.id))
        let resolved = Set(request.postingIDs).intersection(stored)
        guard !resolved.isEmpty else { return }

        revealedPostingIDs = resolved
    }

    /// Opens the posting in the default browser and clears its NEW badge. The badge only clears
    /// once the browser actually took the URL, so a malformed link doesn't quietly lose the flag.
    private func open(_ posting: JobPosting) {
        guard let url = URL(string: posting.url), NSWorkspace.shared.open(url) else {
            FeedLog.logger.error("Could not open posting URL: \(posting.url, privacy: .public)")
            return
        }

        if posting.viewedAt == nil {
            posting.viewedAt = Date()
        }
    }

    /// Dismisses a posting or puts it back. Never deletes: the scrape loop would re-insert a
    /// deleted posting on its next run, and notify about it as if it were new (see
    /// `JobPosting.dismissedAt`).
    private func setDismissed(_ isDismissed: Bool, on posting: JobPosting) {
        posting.dismissedAt = isDismissed ? Date() : nil
        // Only a dismissal made from the feed is undoable inline; restoring already put the
        // row back where the user can see it.
        undoTarget = isDismissed ? posting : nil
    }
}

enum FeedLog {
    static let logger = Logger(subsystem: "com.elizabeth.barnacle", category: "feed")
}

#Preview {
    FeedView()
        .frame(width: 720, height: 420)
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
        .environment(ScrapeCoordinator(container: BarnacleStore.makeContainer(inMemory: true)))
        .environment(NotificationService())
}
