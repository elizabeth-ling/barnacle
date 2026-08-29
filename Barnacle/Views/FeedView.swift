import SwiftUI
import SwiftData

/// Placeholder for the feed. Spec `02` builds the real list: internships newest-first by
/// `effectiveDate`, company filter, sort toggle, click-to-open, and the `+` add-company button.
/// The chrome here is spec `06`'s design system, so `02` styles nothing from scratch.
struct FeedView: View {
    @Query(sort: \JobPosting.dateFirstSeen, order: .reverse)
    private var postings: [JobPosting]

    /// `effectiveDate` is computed, so SwiftData can't sort on it — resolve the newest-first
    /// order here. Spec `02` owns the real list, including the sort toggle.
    private var sortedPostings: [JobPosting] {
        postings.sorted { $0.effectiveDate > $1.effectiveDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader("Feed")

            if postings.isEmpty {
                EmptyState(
                    title: "No postings yet",
                    message: "Add a company to start tracking internships.",
                    systemImage: "tray"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedPostings) { posting in
                            CompactRow(title: posting.title, metadata: metadata(for: posting)) {
                                if let location = posting.location {
                                    Text(location)
                                }
                            }

                            Hairline()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        // Spec `03` opens the add-company modal from here.
        .floatingAddButton(help: "Add a company") {}
    }

    private func metadata(for posting: JobPosting) -> String {
        let date = posting.effectiveDate.formatted(date: .abbreviated, time: .omitted)
        return "\(posting.companyName) \u{00B7} \(date)"
    }
}

#Preview {
    FeedView()
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
}
