import SwiftUI
import SwiftData

/// Placeholder for the applied list. Spec `05` builds the real screen plus the global
/// `⌘J` overlay that adds to it from any app. Chrome comes from spec `06`'s design system.
struct AppliedView: View {
    @Query(sort: \Application.dateApplied, order: .reverse)
    private var applications: [Application]

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader("Applied")

            if applications.isEmpty {
                EmptyState(
                    title: "Nothing logged yet",
                    message: "Applications you log will appear here.",
                    systemImage: "checkmark.circle"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(applications) { application in
                            CompactRow(
                                title: application.jobTitle,
                                metadata: metadata(for: application)
                            ) {
                                Text(application.status.displayName)
                            }

                            Hairline()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }

    private func metadata(for application: Application) -> String {
        let date = application.dateApplied.formatted(date: .abbreviated, time: .omitted)
        return "\(application.companyName) \u{00B7} \(date)"
    }
}

#Preview {
    AppliedView()
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
}
