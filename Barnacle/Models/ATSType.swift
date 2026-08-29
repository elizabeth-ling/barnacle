import Foundation

/// The applicant tracking system backing a company's careers page.
///
/// Detection (spec `03`) classifies a careers URL into one of these, and the scraping
/// engine (spec `01`) picks the matching adapter. `generic` is the fallback for pages
/// that aren't on a known ATS — those get HTML parsing instead of a JSON endpoint.
enum ATSType: String, Codable, CaseIterable, Sendable {
    case greenhouse
    case lever
    case ashby
    case smartRecruiters
    case workday
    case generic

    var displayName: String {
        switch self {
        case .greenhouse: "Greenhouse"
        case .lever: "Lever"
        case .ashby: "Ashby"
        case .smartRecruiters: "SmartRecruiters"
        case .workday: "Workday"
        case .generic: "Generic"
        }
    }
}
