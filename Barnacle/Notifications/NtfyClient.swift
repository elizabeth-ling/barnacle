import Foundation
import OSLog

/// Where a topic string points. The Settings field takes either a bare topic name — published
/// to the public ntfy.sh server — or a full URL, for a self-hosted server (spec `04`).
enum NtfyDestination {
    static let defaultServer = "https://ntfy.sh"

    /// ntfy's own topic rule: letters, digits, `-` and `_`, 1–64 characters.
    private static let topicCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    static func url(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isBareTopic(trimmed) {
            return URL(string: "\(defaultServer)/\(trimmed)")
        }

        // Anything with a slash or a scheme is treated as a server URL. A bare host is not
        // enough — ntfy needs the topic in the path, so `ntfy.example.com` alone is rejected.
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false,
              !url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
        else { return nil }

        return url
    }

    static func isBareTopic(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        return value.unicodeScalars.allSatisfy { topicCharacters.contains($0) }
    }

    /// Public ntfy topics are readable *and* writable by anyone who guesses the name, so the
    /// spec asks for a generated one. 24 characters of base36 is far past guessing; the prefix
    /// is only there so the topic is recognizable in the ntfy iOS app's subscription list.
    static func randomTopic() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let suffix = String((0..<24).map { _ in alphabet.randomElement()! })
        return "barnacle-\(suffix)"
    }
}

/// One HTTP POST per batch — the whole ntfy integration (spec `04`). No account, no
/// credentials, no per-message cost.
enum NtfyClient {
    /// Publishes one message. Throws so callers can report a failed *test*; the scrape path
    /// swallows the error, because a phone push must never take the native notification down
    /// with it.
    static func send(title: String, body: String, to destination: URL) async throws {
        var request = URLRequest(url: destination)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(asciiHeaderValue(title), forHTTPHeaderField: "X-Title")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw NtfyError.httpFailure(statusCode: http.statusCode, detail: serverMessage(in: data))
        }
    }

    /// HTTP header values have no reliable encoding for non-ASCII, and a company name can carry
    /// accents ("Nestlé"), so the title is transliterated before it goes in `X-Title`. The body
    /// is unaffected — it's sent as UTF-8 in the payload, where the em dashes belong.
    static func asciiHeaderValue(_ value: String) -> String {
        let folded = value.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? value
        let printable = folded.unicodeScalars.filter { $0.isASCII && $0.value >= 0x20 && $0.value != 0x7F }
        return String(String.UnicodeScalarView(printable))
    }

    private static func serverMessage(in data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(200))
    }
}

enum NtfyError: LocalizedError {
    case invalidDestination(String)
    case httpFailure(statusCode: Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .invalidDestination(let raw):
            "\u{201C}\(raw)\u{201D} isn\u{2019}t a valid ntfy topic or server URL."
        case .httpFailure(let statusCode, let detail):
            if let detail { "ntfy returned HTTP \(statusCode): \(detail)" } else { "ntfy returned HTTP \(statusCode)." }
        }
    }
}

enum NotificationLog {
    static let logger = Logger(subsystem: "com.elizabeth.barnacle", category: "notifications")
}
