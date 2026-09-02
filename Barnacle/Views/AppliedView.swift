import SwiftUI
import SwiftData
import OSLog

/// The second tab (spec `05`): every application the user has logged, newest first, with the
/// status dropdown, the link, and the notes reachable inline.
///
/// Fully local — nothing here touches the network, so the tab works offline. New entries arrive
/// from two places, the `+` below and the global `⌘J` overlay, and both write through the same
/// `ApplicationFormView`.
struct AppliedView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Application.dateApplied, order: .reverse)
    private var applications: [Application]

    @AppStorage(AppliedSortOrder.storageKey) private var storedSortOrder = AppliedSortOrder.newest.rawValue

    /// Non-nil while the add / edit sheet is up; the mode inside it says which.
    @State private var formModel: ApplicationFormModel?

    @State private var pendingDeletion: Application?

    private var sortOrder: AppliedSortOrder {
        AppliedSortOrder(rawValue: storedSortOrder) ?? .newest
    }

    private var sortOrderBinding: Binding<AppliedSortOrder> {
        Binding(get: { sortOrder }, set: { storedSortOrder = $0.rawValue })
    }

    /// The query already sorts newest-first, so grouping by status only has to be stable —
    /// within a status the newest stays on top.
    private var visibleApplications: [Application] {
        switch sortOrder {
        case .newest:
            return applications
        case .status:
            return applications.sorted { lhs, rhs in
                guard lhs.status != rhs.status else { return false }
                return lhs.status.sortIndex < rhs.status.sortIndex
            }
        }
    }

    private var isDeleting: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Applied") {
                AppliedSortToggle(selection: sortOrderBinding)
            }

            if !applications.isEmpty {
                statusCountsStrip
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .floatingAddButton(help: "Log an application (\u{2318}J from anywhere)") {
            formModel = ApplicationFormModel()
        }
        .sheet(item: $formModel) { model in
            ApplicationFormSheet(model: model)
        }
        .confirmationDialog(
            pendingDeletion.map { "Delete the \($0.companyName) application?" } ?? "Delete application?",
            isPresented: isDeleting,
            presenting: pendingDeletion
        ) { application in
            Button("Delete", role: .destructive) { delete(application) }
            Button("Cancel", role: .cancel) {}
        } message: { application in
            Text("\(application.jobTitle) will be removed from the Applied tab. This can\u{2019}t be undone.")
        }
    }

    /// "12 applied · 3 interviewing" (spec `05`'s light touch). Statuses with nothing in them
    /// are left out, so the line stays short once most applications land in one place.
    private var statusCountsStrip: some View {
        HStack(spacing: 8) {
            Text(statusCounts)
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.textSecondary)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .padding(.vertical, 6)
        .background(Theme.Palette.background)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var statusCounts: String {
        ApplicationStatus.allCases
            .compactMap { status in
                let count = applications.filter { $0.status == status }.count
                guard count > 0 else { return nil }
                return "\(count) \(status.displayName.lowercased())"
            }
            .joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private var content: some View {
        if applications.isEmpty {
            EmptyState(
                title: "Nothing logged yet",
                message: "Press \u{2318}J from any app \u{2014} or use the + \u{2014} to log an application.",
                systemImage: "checkmark.circle"
            ) {
                Button("Log an application") {
                    formModel = ApplicationFormModel()
                }
                .buttonStyle(.barnacleSecondary)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleApplications) { application in
                        ApplicationRow(
                            application: application,
                            onEdit: { formModel = ApplicationFormModel(mode: .edit(application)) },
                            onDelete: { pendingDeletion = application }
                        )

                        Hairline()
                    }
                }
            }
        }
    }

    private func delete(_ application: Application) {
        modelContext.delete(application)
        try? modelContext.save()
        pendingDeletion = nil
    }
}

/// Newest-first by default; grouping by status is spec `05`'s nice-to-have. Persisted, like the
/// Feed's sort, so the choice survives a restart.
enum AppliedSortOrder: String, CaseIterable, Identifiable {
    case newest
    case status

    static let storageKey = "applied.sortOrder"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newest: "Newest"
        case .status: "Status"
        }
    }
}

private struct AppliedSortToggle: View {
    @Binding var selection: AppliedSortOrder

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppliedSortOrder.allCases) { order in
                Button(order.displayName) {
                    selection = order
                }
                .buttonStyle(.quietControl(isActive: selection == order))
                .help(order == .newest ? "Newest first" : "Group by status")
            }
        }
    }
}

enum AppliedLog {
    static let logger = Logger(subsystem: "com.elizabeth.barnacle", category: "applied")
}

#Preview {
    AppliedView()
        .frame(width: 720, height: 420)
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
}
