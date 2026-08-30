import Foundation

/// What checking one careers URL produced (spec `03`, "Validation before saving").
///
/// The spec's rule is that we never silently save something that will never scrape, so every
/// case here is either safe to save or explicitly tells the user what they'd be saving.
enum URLCheckOutcome: Sendable, Equatable {
    /// Not a URL we can parse. Nothing to save — the user has to fix it.
    case invalid(message: String)

    /// Detected, and the adapter's test fetch worked. `internships` is what it found.
    case reachable(detection: ATSDetection, internships: Int)

    /// Detected correctly, but spec `01` hasn't built this ATS's adapter yet. Saving is fine —
    /// the company just won't produce postings until the adapter lands.
    case noAdapterYet(detection: ATSDetection)

    /// Detected, but the test fetch failed. The user can fix the URL or save it as `generic`.
    case unreachable(detection: ATSDetection, message: String)

    var detection: ATSDetection? {
        switch self {
        case .invalid: nil
        case .reachable(let detection, _): detection
        case .noAdapterYet(let detection): detection
        case .unreachable(let detection, _): detection
        }
    }

    /// Whether this URL passed cleanly. Anything else keeps the modal open for a decision.
    var isConfirmed: Bool {
        if case .reachable = self { return true }
        return false
    }

    /// Whether the URL is well-formed enough that "save anyway" is a real option.
    var isSavable: Bool {
        detection != nil
    }
}

/// Runs spec `03`'s Add-time pipeline for one URL: normalize and classify, reclassify a page
/// that merely embeds an ATS, then do a one-shot test fetch with the chosen adapter.
enum CompanyURLChecker {
    static func check(_ raw: String, companyName: String) async -> URLCheckOutcome {
        guard var detection = ATSDetector.detect(raw) else {
            return .invalid(message: "That doesn\u{2019}t look like a careers page URL.")
        }

        // A company's own /careers page may only embed the real ATS. One fetch, best-effort:
        // if it fails or finds nothing, `generic` was already the right answer.
        if !detection.isKnownATS, let url = URL(string: detection.normalizedURL) {
            // Short timeout: this one blocks the modal, and a page that won't answer quickly
            // isn't worth waiting on when `generic` is already the safe answer.
            if let html = try? await PageFetch.html(at: url, timeout: 15),
               let embedded = ATSDetector.detectEmbedded(in: html) {
                detection = ATSDetection(
                    atsType: embedded.atsType,
                    atsToken: embedded.atsToken,
                    // Keep the URL the user typed: it's the page they recognize, and every
                    // adapter works off the token rather than this string.
                    normalizedURL: detection.normalizedURL
                )
            }
        }

        guard let adapter = ATSAdapterRegistry.adapter(for: detection.atsType) else {
            return .noAdapterYet(detection: detection)
        }

        let snapshot = CompanySnapshot(
            id: UUID(),
            name: companyName,
            atsType: detection.atsType,
            atsToken: detection.atsToken,
            careerURLs: [detection.normalizedURL]
        )

        do {
            let jobs = try await adapter.fetchInternships(for: snapshot)
            return .reachable(detection: detection, internships: jobs.count)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .unreachable(detection: detection, message: message)
        }
    }
}
