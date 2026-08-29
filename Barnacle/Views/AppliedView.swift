import SwiftUI
import SwiftData

/// Placeholder for the applied list. Spec `05` builds the real screen plus the global
/// `⌘J` overlay that adds to it from any app.
struct AppliedView: View {
    @Query(sort: \Application.dateApplied, order: .reverse)
    private var applications: [Application]

    var body: some View {
        Group {
            if applications.isEmpty {
                ContentUnavailableView(
                    "Nothing logged yet",
                    systemImage: "checkmark.circle",
                    description: Text("Applications you log will appear here.")
                )
            } else {
                List(applications) { application in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(application.jobTitle)
                        Text("\(application.companyName) · \(application.status.displayName)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Applied")
    }
}

#Preview {
    AppliedView()
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
}
