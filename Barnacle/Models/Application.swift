import Foundation
import SwiftData

/// A job the user applied to. Fully manual and independent of scraped postings —
/// there's deliberately no foreign key to `JobPosting`, because the user may apply
/// to something we never scraped (§5).
@Model
final class Application {
    var id: UUID = UUID()

    /// Typed by the user; may not match any tracked `Company`.
    var companyName: String = ""

    var jobTitle: String = ""

    var url: String?

    var dateApplied: Date = Date()

    var status: ApplicationStatus = ApplicationStatus.applied

    var notes: String?

    init(
        id: UUID = UUID(),
        companyName: String,
        jobTitle: String,
        url: String? = nil,
        dateApplied: Date = Date(),
        status: ApplicationStatus = .applied,
        notes: String? = nil
    ) {
        self.id = id
        self.companyName = companyName
        self.jobTitle = jobTitle
        self.url = url
        self.dateApplied = dateApplied
        self.status = status
        self.notes = notes
    }
}
