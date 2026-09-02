import Foundation

/// Where an application stands. Set by hand — nothing infers this.
enum ApplicationStatus: String, Codable, CaseIterable, Sendable {
    case applied
    case interviewing
    case offer
    case rejected
    case ghosted

    /// Declaration order doubles as pipeline order — applied, interviewing, offer, then the two
    /// endings — which is the order the Applied tab groups by (spec `05`).
    var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var displayName: String {
        switch self {
        case .applied: "Applied"
        case .interviewing: "Interviewing"
        case .offer: "Offer"
        case .rejected: "Rejected"
        case .ghosted: "Ghosted"
        }
    }
}
