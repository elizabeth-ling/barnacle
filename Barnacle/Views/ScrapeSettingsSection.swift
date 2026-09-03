import SwiftUI

/// The Settings section spec `07` asks for: what kind of role, and which countries.
///
/// These are settings, not filters — an internship-seeker becomes a new-grad seeker exactly
/// once, and nobody is open to relocating between Tuesday and Thursday — so there is
/// deliberately no matching control anywhere in the Feed.
///
/// Role level and countries are handed back through callbacks rather than written straight to
/// `preferences`: changing either can delete stored postings, and `SettingsView` owns that
/// confirmation. The unknown-location switch writes directly, because it only shapes what
/// future scrapes keep.
struct ScrapeSettingsSection: View {
    @Bindable var preferences: ScrapePreferences

    let onSelectRoleLevel: (RoleLevel) -> Void
    let onSelectCountries: (Set<String>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            Text("What to look for")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                FieldLabel("Role level")
                RoleLevelSelector(selection: preferences.roleLevel, onSelect: onSelectRoleLevel)
            }

            VStack(alignment: .leading, spacing: 4) {
                FieldLabel("Countries")
                CountrySelector(selection: preferences.countries, onChange: onSelectCountries)
            }

            Toggle(isOn: $preferences.includeUnknownLocation) {
                Text("Include postings with an unrecognized location")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(Theme.Palette.accent)

            Text("Some boards don\u{2019}t state a country. Keeping these means the odd posting from elsewhere rather than a missed one nearby \u{2014} the row always shows the location it was given.")
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Two options, mutually exclusive — the accent marks the live one, as everywhere else.
struct RoleLevelSelector: View {
    let selection: RoleLevel
    let onSelect: (RoleLevel) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RoleLevel.allCases) { level in
                Button(level.displayName) {
                    onSelect(level)
                }
                .buttonStyle(.quietControl(isActive: level == selection))
                .help(level == .internship
                      ? "Track internship postings"
                      : "Track new-grad and entry-level postings")
            }
        }
    }
}

/// A compact multi-select over countries: the United States and Canada pinned as the common
/// case, anything else added by typing. Never a 200-row scroll.
struct CountrySelector: View {
    let selection: Set<String>
    let onChange: (Set<String>) -> Void

    @State private var searchText = ""

    /// Pinned first, then whatever else is selected, alphabetically — so a chosen country never
    /// disappears back into the search field.
    private var visibleCodes: [String] {
        let extra = selection
            .subtracting(CountryCatalog.pinnedCodes)
            .sorted { CountryCatalog.name(for: $0) < CountryCatalog.name(for: $1) }
        return CountryCatalog.pinnedCodes + extra
    }

    private var matches: [CountryCatalog.Country] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return Array(
            CountryCatalog.all
                .filter { country in
                    guard !visibleCodes.contains(country.code) else { return false }
                    return country.name.localizedCaseInsensitiveContains(query)
                        || country.code.caseInsensitiveCompare(query) == .orderedSame
                }
                .prefix(6)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 6, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(visibleCodes, id: \.self) { code in
                    chip(for: code)
                }
            }

            TextField("Add another country", text: $searchText)
                .barnacleField()
                .frame(maxWidth: 220)

            if !matches.isEmpty {
                VStack(spacing: 0) {
                    ForEach(matches) { country in
                        Button {
                            onChange(selection.union([country.code]))
                            searchText = ""
                        } label: {
                            Text(country.name)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 220, alignment: .leading)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                }
            } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("No country matches that.")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private func chip(for code: String) -> some View {
        let isSelected = selection.contains(code)
        return Button {
            onChange(isSelected ? selection.subtracting([code]) : selection.union([code]))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9, weight: .semibold))
                Text(CountryCatalog.name(for: code))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.quietControl(isActive: isSelected))
        .help(isSelected ? "Stop watching \(CountryCatalog.name(for: code))" : "Watch \(CountryCatalog.name(for: code))")
    }
}

#Preview("Role and location settings") {
    struct Host: View {
        @State private var preferences = ScrapePreferences()

        var body: some View {
            ScrapeSettingsSection(
                preferences: preferences,
                onSelectRoleLevel: { preferences.roleLevel = $0 },
                onSelectCountries: { preferences.countries = $0 }
            )
            .padding(Theme.Metrics.screenPadding)
            .frame(width: 460, alignment: .topLeading)
            .screenBackground()
        }
    }

    return Host()
}
