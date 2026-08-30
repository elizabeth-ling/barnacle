import Foundation

/// How the Feed writes a posting's effective date (spec `02`): relative while it's fresh
/// ("2h ago", "Yesterday"), absolute once it isn't ("Aug 21"). The unabbreviated timestamp
/// goes in the row's hover tooltip.
enum PostingDateFormat {
    /// Compact relative form for the row's trailing date.
    static func relative(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let elapsed = now.timeIntervalSince(date)

        // A source stamping ahead of our clock reads as brand new, never "in 3 hours".
        if elapsed < 60 { return "Just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3600))h ago" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        // Same year is the common case, so drop the year and keep the row narrow.
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// The full timestamp behind the row's tooltip.
    static func absolute(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// "Updated 3:04 PM" for today's scrape; falls back to a date once it isn't today.
    static func lastUpdated(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
