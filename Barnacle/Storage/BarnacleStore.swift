import Foundation
import SwiftData

/// The app's single SwiftData container.
///
/// **Why SwiftData and not GRDB:** the data model is three small entities with no joins
/// worth optimizing, so the boilerplate savings win. If the model ever outgrows that, the
/// swap point is here plus the `@Query` calls in the views — nothing else touches storage.
enum BarnacleStore {
    static let schema = Schema([
        Company.self,
        JobPosting.self,
        Application.self,
    ])

    /// Local-only, on disk. No sync, no account — everything stays on this machine (§1).
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the Barnacle model container: \(error)")
        }
    }

    static let shared: ModelContainer = makeContainer()
}
