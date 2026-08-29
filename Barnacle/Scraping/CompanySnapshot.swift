import Foundation

/// The company fields an adapter needs, as an immutable `Sendable` value.
///
/// **Why this exists instead of passing `Company`:** SwiftData models belong to the
/// `ModelContext` that fetched them and aren't safe to touch from another thread. Adapters
/// run as `nonisolated async` network calls off the scrape actor, so they get a snapshot
/// taken inside the actor rather than the live model object. It also keeps the whole
/// adapter layer free of SwiftData, so adapters can be exercised on their own.
struct CompanySnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let atsType: ATSType
    let atsToken: String?
    let careerURLs: [String]
}
