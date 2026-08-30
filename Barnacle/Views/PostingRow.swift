import SwiftUI

/// One Feed row (spec `02`): job title primary, company underneath, location and the effective
/// date trailing, a NEW badge until the user opens it. All chrome comes from `CompactRow`.
struct PostingRow: View {
    let posting: JobPosting
    let onOpen: () -> Void

    var body: some View {
        CompactRow(
            title: posting.title,
            metadata: posting.companyName,
            isNew: posting.isUnviewed,
            action: onOpen
        ) {
            HStack(spacing: 6) {
                if let location = posting.location, !location.isEmpty {
                    Text(location)
                }

                Text(PostingDateFormat.relative(posting.effectiveDate))
                    // Spec `02`: the full timestamp on hover.
                    .help(PostingDateFormat.absolute(posting.effectiveDate))
            }
        }
    }
}

#Preview("Posting rows") {
    let company = UUID()
    return VStack(spacing: 0) {
        PostingRow(
            posting: JobPosting(
                companyID: company,
                companyName: "Stripe",
                title: "Software Engineer Intern, Payments",
                url: "https://example.com",
                datePosted: Date().addingTimeInterval(-2 * 3600),
                location: "Seattle, WA",
                rawID: "1"
            ),
            onOpen: {}
        )
        Hairline()
        PostingRow(
            posting: JobPosting(
                companyID: company,
                companyName: "Ramp",
                title: "Product Design Intern",
                url: "https://example.com",
                datePosted: Date().addingTimeInterval(-30 * 3600),
                location: "New York, NY",
                rawID: "2",
                viewedAt: Date()
            ),
            onOpen: {}
        )
    }
    .frame(width: 480)
    .screenBackground()
}
