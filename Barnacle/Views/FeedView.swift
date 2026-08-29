import SwiftUI
import SwiftData

/// Placeholder for the feed. Spec `02` builds the real list: internships newest-first by
/// `effectiveDate`, company filter, sort toggle, click-to-open, and the `+` add-company button.
struct FeedView: View {
    @Query(sort: \JobPosting.dateFirstSeen, order: .reverse)
    private var postings: [JobPosting]

    var body: some View {
        Group {
            if postings.isEmpty {
                ContentUnavailableView(
                    "No postings yet",
                    systemImage: "tray",
                    description: Text("Add a company to start tracking internships.")
                )
            } else {
                List(postings) { posting in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(posting.title)
                        Text(posting.companyName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Feed")
    }
}

#Preview {
    FeedView()
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
}
