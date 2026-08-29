import SwiftUI
import SwiftData

/// Placeholder for the feed. Spec `02` builds the real list: internships newest-first by
/// `effectiveDate`, company filter, sort toggle, click-to-open, and the `+` add-company button.
struct FeedView: View {
    @Query(sort: \JobPosting.dateFirstSeen, order: .reverse)
    private var postings: [JobPosting]

    /// `effectiveDate` is computed, so SwiftData can't sort on it — resolve the newest-first
    /// order here. Spec `02` owns the real list, including the sort toggle.
    private var sortedPostings: [JobPosting] {
        postings.sorted { $0.effectiveDate > $1.effectiveDate }
    }

    var body: some View {
        Group {
            if postings.isEmpty {
                ContentUnavailableView(
                    "No postings yet",
                    systemImage: "tray",
                    description: Text("Add a company to start tracking internships.")
                )
            } else {
                List(sortedPostings) { posting in
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
