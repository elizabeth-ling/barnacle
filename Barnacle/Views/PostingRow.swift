import SwiftUI

/// One Feed row (spec `02`): job title primary, company underneath, location and the effective
/// date trailing, a NEW badge until the user opens it. All chrome comes from `CompactRow`.
///
/// The trailing slot also carries the dismiss control: an `×` that appears on hover and takes
/// the posting out of the feed, or, in the Dismissed view, the arrow that puts it back. It is
/// only in the layout while the row is hovered — an always-reserved slot left a visible gap
/// between the date and the row edge on every idle row.
struct PostingRow: View {
    let posting: JobPosting
    let onOpen: () -> Void

    /// Called with the state the user asked for: `true` to dismiss, `false` to restore.
    let onSetDismissed: (Bool) -> Void

    var body: some View {
        CompactRow(
            title: posting.title,
            metadata: posting.companyName,
            isNew: posting.isUnviewed,
            action: onOpen
        ) { isRowHovered in
            HStack(spacing: 6) {
                if let location = posting.location, !location.isEmpty {
                    Text(location)
                }

                Text(PostingDateFormat.relative(posting.effectiveDate))
                    // Spec `02`: the full timestamp on hover.
                    .help(PostingDateFormat.absolute(posting.effectiveDate))

                // Present only while the row is hovered, so an idle row's date sits flush
                // against the row padding instead of leaving a gap where a hidden control
                // would be. The metadata slides over to make room, animated by `CompactRow`'s
                // hover animation.
                if isRowHovered {
                    dismissControl
                }
            }
        }
        // Right-click carries the same action, since a hover-only control is easy to miss.
        .contextMenu {
            Button(posting.isDismissed ? "Restore to Feed" : "Dismiss") {
                onSetDismissed(!posting.isDismissed)
            }
        }
    }

    private var dismissControl: some View {
        Button {
            onSetDismissed(!posting.isDismissed)
        } label: {
            Image(systemName: posting.isDismissed ? "arrow.uturn.backward" : "xmark")
                .font(.system(size: 9, weight: .semibold))
        }
        .buttonStyle(.quietControl())
        .help(posting.isDismissed ? "Restore this posting to the feed" : "Dismiss this posting")
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
            onOpen: {},
            onSetDismissed: { _ in }
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
            onOpen: {},
            onSetDismissed: { _ in }
        )
        Hairline()
        PostingRow(
            posting: JobPosting(
                companyID: company,
                companyName: "Notion",
                title: "ML Research Intern",
                url: "https://example.com",
                datePosted: Date().addingTimeInterval(-52 * 3600),
                rawID: "3",
                viewedAt: Date(),
                dismissedAt: Date()
            ),
            onOpen: {},
            onSetDismissed: { _ in }
        )
    }
    .frame(width: 480)
    .screenBackground()
}
