import Foundation
import OSLog
import SwiftData

/// Runs one scrape pass on its own `ModelContext`, off the main thread (spec `01`).
///
/// `@ModelActor` gives this actor a context bound to its own executor, so fetching,
/// inserting, and saving all happen away from the main actor. Saves are merged into the
/// main context by SwiftData, which is what refreshes the Feed's `@Query` reactively.
@ModelActor
actor ScrapeRunner {
    /// Politeness delay between companies (§7). Only applied *between* companies.
    private static let betweenCompaniesDelay: ClosedRange<Double> = 1...2

    /// Scrapes every active company in turn.
    ///
    /// Never throws: a company that fails is logged and recorded in `ScrapeRun.failures`,
    /// and the run continues with the next one. The coordinator serializes calls, so this
    /// is never re-entered while a run is in flight.
    func scrapeAll() async -> ScrapeRun {
        let startedAt = Date()
        let companies = activeCompanies()

        var newPostings: [NewPosting] = []
        var failures: [ScrapeFailure] = []

        for (index, company) in companies.enumerated() {
            if index > 0 {
                try? await Task.sleep(for: .seconds(Double.random(in: Self.betweenCompaniesDelay)))
            }

            let name = company.name
            do {
                let fresh = try await scrape(company)
                newPostings.append(contentsOf: fresh)
                ScrapeLog.logger.info("Scraped \(name, privacy: .public): \(fresh.count) new")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                failures.append(ScrapeFailure(companyName: name, message: message))
                ScrapeLog.logger.error("Scrape failed for \(name, privacy: .public): \(message, privacy: .public)")
            }
        }

        return ScrapeRun(
            startedAt: startedAt,
            finishedAt: Date(),
            companiesScraped: companies.count,
            newPostings: newPostings.sorted { $0.effectiveDate > $1.effectiveDate },
            failures: failures
        )
    }

    // MARK: - One company

    private func activeCompanies() -> [Company] {
        let descriptor = FetchDescriptor<Company>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            ScrapeLog.logger.error("Couldn't fetch companies: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetches, dedups, inserts, and saves for one company. Returns only genuinely new
    /// postings — and only once the save succeeded, so we never notify about a posting we
    /// failed to store.
    private func scrape(_ company: Company) async throws -> [NewPosting] {
        guard let adapter = ATSAdapterRegistry.adapter(for: company.atsType) else {
            throw ScrapeError.unsupportedATS(company.atsType)
        }

        let snapshot = CompanySnapshot(company)
        let scraped = try await adapter.fetchInternships(for: snapshot)
        let now = Date()

        var fresh: [NewPosting] = []
        var seenRawIDs: Set<String> = []

        for job in scraped where !job.rawID.isEmpty {
            // Guards against a source listing the same id twice in one payload.
            guard seenRawIDs.insert(job.rawID).inserted else { continue }
            guard try !isStored(companyID: snapshot.id, rawID: job.rawID) else { continue }

            let posting = JobPosting(
                companyID: snapshot.id,
                companyName: snapshot.name,
                title: job.title,
                url: job.url,
                datePosted: job.datePosted,
                dateFirstSeen: now,
                location: job.location,
                rawID: job.rawID
            )
            modelContext.insert(posting)
            fresh.append(
                NewPosting(
                    id: posting.id,
                    companyName: posting.companyName,
                    title: posting.title,
                    url: posting.url,
                    effectiveDate: posting.effectiveDate,
                    location: posting.location
                )
            )
        }

        reconcileClosed(companyID: snapshot.id, stillListed: seenRawIDs, now: now)
        company.lastScrapedAt = now
        try modelContext.save()

        return fresh
    }

    /// The dedup half of §5: a posting is new only if nothing stored shares its
    /// `(companyID, rawID)` pair.
    private func isStored(companyID: UUID, rawID: String) throws -> Bool {
        var descriptor = FetchDescriptor<JobPosting>(
            predicate: JobPosting.existsPredicate(companyID: companyID, rawID: rawID)
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetchCount(descriptor) > 0
    }

    /// Postings are never deleted (§5) — one that has dropped off the source is stamped
    /// `closedAt` instead, and un-stamped if it comes back. Only runs after a successful
    /// fetch, so a network error can't mass-close a company's postings.
    private func reconcileClosed(companyID: UUID, stillListed: Set<String>, now: Date) {
        let descriptor = FetchDescriptor<JobPosting>(
            predicate: #Predicate { $0.companyID == companyID }
        )
        guard let stored = try? modelContext.fetch(descriptor) else { return }

        for posting in stored {
            if stillListed.contains(posting.rawID) {
                posting.closedAt = nil
            } else if posting.closedAt == nil {
                posting.closedAt = now
            }
        }
    }
}

private extension CompanySnapshot {
    /// Taken inside the actor so the adapter never touches the live SwiftData model.
    init(_ company: Company) {
        self.init(
            id: company.id,
            name: company.name,
            atsType: company.atsType,
            atsToken: company.atsToken,
            careerURLs: company.careerURLs
        )
    }
}
