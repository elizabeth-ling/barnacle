import SwiftUI

/// Feed sort order over the effective date (`datePosted ?? dateFirstSeen`). Persisted across
/// launches by `@AppStorage` in `FeedView`.
enum FeedSortOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest

    /// The `@AppStorage` key. Lives here so the view and the default can't drift apart.
    static let storageKey = "feed.sortOrder"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        }
    }
}

/// Newest ↔ Oldest, as two quiet controls — spec `06` wants the accent only on the active one.
struct FeedSortToggle: View {
    @Binding var selection: FeedSortOrder

    var body: some View {
        HStack(spacing: 4) {
            ForEach(FeedSortOrder.allCases) { order in
                Button(order.displayName) {
                    selection = order
                }
                .buttonStyle(.quietControl(isActive: selection == order))
                .help("Sort \(order.displayName.lowercased()) first")
            }
        }
    }
}

/// The company filter: a quiet control opening a popover of tracked companies plus
/// "All companies," narrowed by typing (spec `02`).
///
/// A plain `Menu` can't hold a working text field on macOS, so this is a button + popover.
struct CompanyFilterControl: View {
    let companies: [Company]
    @Binding var selection: UUID?

    /// Spec `03` puts company management behind the filter, since that's where tracked
    /// companies are already visible. Defaulted so previews and tests can ignore it.
    var onManageCompanies: () -> Void = {}

    @State private var isPresented = false
    @State private var searchText = ""

    private var selectedName: String {
        guard let selection, let company = companies.first(where: { $0.id == selection }) else {
            return "All companies"
        }
        return company.name
    }

    private var matches: [Company] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return companies }
        return companies.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(selectedName)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .buttonStyle(.quietControl(isActive: selection != nil))
        .help("Filter by company")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popover
                // A popover is its own window, so it doesn't inherit the main window's pinned
                // appearance — same light-only caveat as `RootView` and `SettingsView`.
                .preferredColorScheme(.light)
        }
    }

    private var popover: some View {
        VStack(spacing: 0) {
            TextField("Filter companies", text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .onSubmit { select(matches.first?.id) }

            Hairline()

            ScrollView {
                LazyVStack(spacing: 0) {
                    FilterOption(name: "All companies", isSelected: selection == nil) {
                        select(nil)
                    }

                    if !matches.isEmpty {
                        Hairline()
                    }

                    ForEach(matches) { company in
                        FilterOption(name: company.name, isSelected: selection == company.id) {
                            select(company.id)
                        }
                    }

                    if matches.isEmpty && !searchText.isEmpty {
                        Text("No companies match.")
                            .font(Theme.Typography.metadata)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 220)

            Hairline()

            FilterOption(name: "Manage companies\u{2026}", isSelected: false) {
                isPresented = false
                onManageCompanies()
            }
        }
        .frame(width: 220)
        .background(Theme.Palette.surface)
    }

    private func select(_ id: UUID?) {
        selection = id
        searchText = ""
        isPresented = false
    }

    /// One line of the popover. Hover matches `CompactRow`'s, at popover density.
    private struct FilterOption: View {
        let name: String
        let isSelected: Bool
        let action: () -> Void

        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(isSelected ? Theme.Palette.accent : Theme.Palette.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.Palette.accent)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHovered ? Theme.Palette.surfaceAlt : Theme.Palette.surface)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(Theme.Metrics.hoverAnimation, value: isHovered)
        }
    }
}

/// "Refresh now" plus the run state (spec `02`): a subtle spinner while a scrape is in flight,
/// the last-updated time when idle. The schedule itself belongs to `ScrapeCoordinator` (spec `01`).
struct FeedRefreshControl: View {
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator

    var body: some View {
        HStack(spacing: 6) {
            if scrapeCoordinator.isScraping {
                ProgressView()
                    .controlSize(.small)
            } else if let finishedAt = scrapeCoordinator.lastRun?.finishedAt {
                Text("Updated \(PostingDateFormat.lastUpdated(finishedAt))")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .help(PostingDateFormat.absolute(finishedAt))
            }

            Button {
                Task { await scrapeCoordinator.refreshNow() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.quietControl())
            .disabled(scrapeCoordinator.isScraping)
            .help("Refresh now")
        }
    }
}

#Preview("Feed controls") {
    // A host view, because a `#Preview` body can't own `@State`.
    struct Host: View {
        @State private var sortOrder = FeedSortOrder.newest
        @State private var companyFilter: UUID?

        var body: some View {
            HStack(spacing: 6) {
                CompanyFilterControl(companies: [], selection: $companyFilter)
                FeedSortToggle(selection: $sortOrder)
            }
            .padding(24)
            .screenBackground()
        }
    }

    return Host()
}
