import SwiftUI
import SwiftData
import AppKit
import OSLog

/// The main dashboard (spec `02`): internships from tracked companies, newest-first by effective
/// date, filtered by company, click-to-open. Every pixel of chrome comes from spec `06`.
struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator

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

    @State private var isAddingCompany = false
    @State private var isManagingCompanies = false

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

    private var visiblePostings: [JobPosting] {
        postings
            .filter { activeCompanyFilter == nil || $0.companyID == activeCompanyFilter }
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
                    FeedSortToggle(selection: sortOrderBinding)
                    FeedRefreshControl()
                }
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .floatingAddButton(help: "Add a company") { isAddingCompany = true }
        .sheet(isPresented: $isAddingCompany) {
            AddCompanyView()
        }
        .sheet(isPresented: $isManagingCompanies) {
            ManageCompaniesView()
        }
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
        } else if visiblePostings.isEmpty {
            EmptyState(
                title: "Nothing from this company yet",
                message: "Switch back to all companies to see the rest of the feed.",
                systemImage: "line.3.horizontal.decrease"
            ) {
                Button("All companies") {
                    companyFilter = nil
                }
                .buttonStyle(.barnacleSecondary)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visiblePostings) { posting in
                        PostingRow(posting: posting) { open(posting) }
                        Hairline()
                    }
                }
            }
        }
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
}

enum FeedLog {
    static let logger = Logger(subsystem: "com.elizabeth.barnacle", category: "feed")
}

#Preview {
    FeedView()
        .frame(width: 720, height: 420)
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
        .environment(ScrapeCoordinator(container: BarnacleStore.makeContainer(inMemory: true)))
}
