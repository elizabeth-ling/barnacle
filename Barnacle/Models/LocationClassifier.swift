import Foundation

/// Turns an ATS's free-text location into countries (spec `07`).
///
/// The data is messy on purpose-built boards and worse everywhere else — `San Francisco,
/// California`, `US-Remote`, `Bengaluru, India`, `Dublin`, `N/A`, `Mountain View, California;
/// San Francisco, California` are all real values. So this answers honestly rather than
/// confidently: `nil` means **unknown**, not "nowhere", and `ScrapeFilter` only ever rejects a
/// posting whose every location resolved *and* landed outside the allowed set.
enum LocationClassifier {
    /// What one location string resolved to.
    struct Match: Sendable, Equatable {
        /// Every country the string named confidently. Empty when nothing resolved.
        var countries: Set<String> = []

        /// True when at least one part of the string didn't resolve — including a posting with
        /// no location at all. This is what keeps an oddly-worded San Francisco internship in
        /// the feed instead of silently dropping it.
        var hasUnknown = false

        var isRemote = false

        /// The country to store on the posting: one the user is watching if there is one, so
        /// the stored value explains why the posting was kept. Sorted for determinism.
        func primaryCountry(preferring allowed: Set<String>) -> String? {
            countries.sorted().first { allowed.contains($0) } ?? countries.sorted().first
        }
    }

    /// Classifies one posting's location.
    ///
    /// - Parameters:
    ///   - raw: the ATS's text, whatever shape it came in.
    ///   - structuredCountries: countries the ATS stated outright (Ashby's
    ///     `address.postalAddress.addressCountry`). Authoritative — a source that says the
    ///     country beats any guess made from the text.
    ///   - isRemote: the ATS's own remote flag, if it has one.
    static func classify(
        _ raw: String?,
        structuredCountries: [String] = [],
        isRemote: Bool = false
    ) -> Match {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = isRemote || mentionsRemote(text)

        let structured = Set(structuredCountries.compactMap(countryCode(forCountry:)))
        if !structured.isEmpty {
            return Match(countries: structured, hasUnknown: false, isRemote: remote)
        }

        guard !text.isEmpty else {
            return Match(countries: [], hasUnknown: true, isRemote: remote)
        }

        var countries: Set<String> = []
        var hasUnknown = false
        for part in parts(of: text) {
            if let code = country(in: part) {
                countries.insert(code)
            } else {
                hasUnknown = true
            }
        }
        // A string that produced no parts at all (punctuation, "—") is unknown, not empty.
        if countries.isEmpty {
            hasUnknown = true
        }
        return Match(countries: countries, hasUnknown: hasUnknown, isRemote: remote)
    }

    /// A country the ATS named outright, or nil if we don't recognize it.
    static func countryCode(forCountry raw: String) -> String? {
        countryCodes[normalize(raw)]
    }

    // MARK: - One location

    /// Resolution order, first hit wins: explicit country token, then US state / Canadian
    /// province, then the city gazetteer.
    ///
    /// Tokens are walked **last to first** because that's how location strings are written —
    /// the qualifier ("City, State", "City, Country") comes last, so "Mexico, MO" resolves on
    /// `MO` rather than on `Mexico`.
    ///
    /// Inside a multi-token part, a two-letter token is read as a state or province *before* a
    /// country code: "San Francisco, CA" is California far more often than it is Canada. A
    /// two-letter token that is the whole string keeps the country reading, which is what makes
    /// Stripe's bare `US` resolve.
    private static func country(in part: String) -> String? {
        let tokens = tokenize(part)
        guard !tokens.isEmpty else { return nil }
        let isLoneToken = tokens.count == 1

        for token in tokens.reversed() {
            if !isLoneToken, let code = subnationalCountries[token] { return code }
            if let code = countryCodes[token] { return code }
            if isLoneToken, let code = subnationalCountries[token] { return code }
            if let code = cityCountries[token] { return code }
        }
        return nil
    }

    private static func mentionsRemote(_ text: String) -> Bool {
        text.lowercased().range(of: "\\bremote\\b", options: .regularExpression) != nil
    }

    /// Multi-location strings split on `;`, `/`, `|`, and ` and `. Each part is classified
    /// separately and the posting carries the full set.
    private static func parts(of text: String) -> [String] {
        var working = text
        for separator in [";", "|", "/"] {
            working = working.replacingOccurrences(of: separator, with: "\u{1}")
        }
        working = working.replacingOccurrences(of: " and ", with: "\u{1}", options: [.caseInsensitive])
        return working
            .components(separatedBy: "\u{1}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// One part into its comma- and hyphen-separated pieces, normalized. Hyphens matter:
    /// `US-Remote` has to yield `us`.
    private static func tokenize(_ part: String) -> [String] {
        part
            .components(separatedBy: CharacterSet(charactersIn: ",-\u{2013}\u{2014}()[]"))
            .map(normalize)
            .filter { !$0.isEmpty }
    }

    /// Lowercased, punctuation-light, single-spaced — so `U.S.` and `us` are the same token.
    private static func normalize(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Tables

    /// Country names and codes, built from the system's ISO region list so we don't hand-type
    /// 250 rows. Names are taken in English deliberately: the boards are in English, whatever
    /// the Mac's locale is.
    private static let countryCodes: [String: String] = {
        var table: [String: String] = [:]
        let english = Locale(identifier: "en_US")

        for region in Locale.Region.isoRegions
        where region.identifier.count == 2 && region.identifier.allSatisfy(\.isLetter) {
            let code = region.identifier.uppercased()
            table[code.lowercased()] = code
            if let name = english.localizedString(forRegionCode: code) {
                let key = normalize(name)
                if !ambiguousCountryNames.contains(key) {
                    table[key] = code
                }
            }
        }

        for (alias, code) in countryAliases {
            table[normalize(alias)] = code
        }
        return table
    }()

    /// Country names we refuse to read as countries, because they are far more often a US
    /// place: "Atlanta, Georgia" is not Tbilisi, and "Lebanon, NH" is not Beirut. Both then
    /// fall through to the state table or to unknown, which is the safe direction.
    private static let ambiguousCountryNames: Set<String> = ["georgia", "lebanon"]

    private static let countryAliases: [String: String] = [
        "usa": "US", "us of a": "US", "united states of america": "US", "u s a": "US",
        "uk": "GB", "great britain": "GB", "britain": "GB", "england": "GB",
        "scotland": "GB", "wales": "GB", "northern ireland": "GB",
        "republic of ireland": "IE",
        "holland": "NL", "the netherlands": "NL",
        "uae": "AE",
        "south korea": "KR", "korea": "KR",
        "czech republic": "CZ",
        "russian federation": "RU",
    ]

    /// US states and Canadian provinces, name and postal abbreviation, mapped to their country.
    /// This is what resolves `San Francisco, California` and `Toronto, Ontario`.
    private static let subnationalCountries: [String: String] = {
        var table: [String: String] = [:]
        let usStates = [
            "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR",
            "california": "CA", "colorado": "CO", "connecticut": "CT", "delaware": "DE",
            "florida": "FL", "georgia": "GA", "hawaii": "HI", "idaho": "ID",
            "illinois": "IL", "indiana": "IN", "iowa": "IA", "kansas": "KS",
            "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD",
            "massachusetts": "MA", "michigan": "MI", "minnesota": "MN", "mississippi": "MS",
            "missouri": "MO", "montana": "MT", "nebraska": "NE", "nevada": "NV",
            "new hampshire": "NH", "new jersey": "NJ", "new mexico": "NM", "new york": "NY",
            "north carolina": "NC", "north dakota": "ND", "ohio": "OH", "oklahoma": "OK",
            "oregon": "OR", "pennsylvania": "PA", "rhode island": "RI", "south carolina": "SC",
            "south dakota": "SD", "tennessee": "TN", "texas": "TX", "utah": "UT",
            "vermont": "VT", "virginia": "VA", "washington": "WA", "west virginia": "WV",
            "wisconsin": "WI", "wyoming": "WY",
            "district of columbia": "DC", "washington dc": "DC", "puerto rico": "PR",
        ]
        for (name, abbreviation) in usStates {
            table[name] = "US"
            table[abbreviation.lowercased()] = "US"
        }

        let provinces = [
            "alberta": "AB", "british columbia": "BC", "manitoba": "MB",
            "new brunswick": "NB", "newfoundland and labrador": "NL", "nova scotia": "NS",
            "northwest territories": "NT", "nunavut": "NU", "ontario": "ON",
            "prince edward island": "PE", "quebec": "QC", "saskatchewan": "SK", "yukon": "YT",
        ]
        for (name, abbreviation) in provinces {
            table[name] = "CA"
            table[abbreviation.lowercased()] = "CA"
        }
        return table
    }()

    /// A small curated table of unambiguous hubs — the last resort before unknown.
    ///
    /// Deliberately excludes ambiguous names: **`Dublin` is not here** (Ireland vs. Dublin,
    /// California), and neither are `London` (UK vs. Ontario), `Vancouver` (BC vs. Washington),
    /// `Cambridge`, `Manchester`, `Birmingham`, or `Waterloo`. They resolve to unknown, which is
    /// the honest answer — and an unknown posting is kept, not dropped.
    private static let cityCountries: [String: String] = [
        // Canada
        "toronto": "CA", "montreal": "CA", "montr\u{e9}al": "CA", "ottawa": "CA",
        "calgary": "CA", "edmonton": "CA", "winnipeg": "CA", "halifax": "CA",
        "quebec city": "CA", "mississauga": "CA",
        // United States
        "san francisco": "US", "new york city": "US", "nyc": "US", "brooklyn": "US",
        "seattle": "US", "chicago": "US", "boston": "US", "austin": "US", "denver": "US",
        "atlanta": "US", "los angeles": "US", "san diego": "US", "san jose": "US",
        "palo alto": "US", "mountain view": "US", "menlo park": "US", "sunnyvale": "US",
        "cupertino": "US", "redmond": "US", "philadelphia": "US", "houston": "US",
        "dallas": "US", "miami": "US", "pittsburgh": "US",
        // India
        "bengaluru": "IN", "bangalore": "IN", "hyderabad": "IN", "pune": "IN",
        "gurgaon": "IN", "gurugram": "IN", "noida": "IN", "mumbai": "IN",
        "chennai": "IN", "new delhi": "IN", "kolkata": "IN", "ahmedabad": "IN",
        // Asia-Pacific
        "singapore": "SG", "tokyo": "JP", "osaka": "JP", "kyoto": "JP", "seoul": "KR",
        "beijing": "CN", "shanghai": "CN", "shenzhen": "CN", "guangzhou": "CN",
        "hangzhou": "CN", "hong kong": "HK", "taipei": "TW", "bangkok": "TH",
        "manila": "PH", "cebu": "PH", "jakarta": "ID", "kuala lumpur": "MY",
        "hanoi": "VN", "ho chi minh city": "VN",
        "sydney": "AU", "melbourne": "AU", "brisbane": "AU", "canberra": "AU",
        "auckland": "NZ",
        // Europe
        "amsterdam": "NL", "rotterdam": "NL", "utrecht": "NL", "eindhoven": "NL",
        "berlin": "DE", "munich": "DE", "m\u{fc}nchen": "DE", "hamburg": "DE",
        "frankfurt": "DE", "cologne": "DE", "stuttgart": "DE",
        "paris": "FR", "lyon": "FR", "toulouse": "FR",
        "madrid": "ES", "barcelona": "ES", "milan": "IT", "rome": "IT", "turin": "IT",
        "lisbon": "PT", "porto": "PT", "brussels": "BE", "ghent": "BE", "leuven": "BE",
        "zurich": "CH", "z\u{fc}rich": "CH", "geneva": "CH", "lausanne": "CH",
        "vienna": "AT", "prague": "CZ", "warsaw": "PL", "krakow": "PL", "krak\u{f3}w": "PL",
        "wroclaw": "PL", "gdansk": "PL", "budapest": "HU", "bucharest": "RO",
        "sofia": "BG", "belgrade": "RS", "zagreb": "HR", "tallinn": "EE",
        "riga": "LV", "vilnius": "LT", "kyiv": "UA", "kiev": "UA",
        "stockholm": "SE", "gothenburg": "SE", "copenhagen": "DK", "oslo": "NO",
        "helsinki": "FI", "athens": "GR", "istanbul": "TR", "ankara": "TR",
        "edinburgh": "GB", "glasgow": "GB", "leeds": "GB",
        // Middle East, Africa, Latin America
        "tel aviv": "IL", "jerusalem": "IL", "haifa": "IL",
        "dubai": "AE", "abu dhabi": "AE", "cairo": "EG",
        "lagos": "NG", "abuja": "NG", "nairobi": "KE",
        "cape town": "ZA", "johannesburg": "ZA", "pretoria": "ZA", "durban": "ZA",
        "sao paulo": "BR", "s\u{e3}o paulo": "BR", "rio de janeiro": "BR",
        "mexico city": "MX", "guadalajara": "MX", "monterrey": "MX",
        "buenos aires": "AR", "santiago": "CL", "bogota": "CO", "bogot\u{e1}": "CO",
        "medellin": "CO", "lima": "PE",
    ]
}

/// Every country the picker can offer, name and code, in one place (spec `07`'s Settings
/// multi-select). Built from the same ISO list the classifier reads.
enum CountryCatalog {
    struct Country: Identifiable, Hashable, Sendable {
        let code: String
        let name: String
        var id: String { code }
    }

    /// The common case, pinned to the top of the picker.
    static let pinnedCodes = ["US", "CA"]

    static let all: [Country] = {
        let english = Locale(identifier: "en_US")
        return Locale.Region.isoRegions
            .filter { $0.identifier.count == 2 && $0.identifier.allSatisfy(\.isLetter) }
            .compactMap { region -> Country? in
                let code = region.identifier.uppercased()
                guard let name = english.localizedString(forRegionCode: code) else { return nil }
                return Country(code: code, name: name)
            }
            .sorted { $0.name < $1.name }
    }()

    static func name(for code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }

    /// Names a set of countries for a settings line: "United States, Canada".
    static func names(for codes: Set<String>) -> String {
        codes.map(name(for:)).sorted().joined(separator: ", ")
    }
}
