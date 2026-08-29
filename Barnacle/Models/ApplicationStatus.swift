import Foundation

/// Where an application stands. Set by hand — nothing infers this.
enum ApplicationStatus: String, Codable, CaseIterable, Sendable {
    case applied
    case interviewing
    case offer
    case rejected
    case ghosted

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
