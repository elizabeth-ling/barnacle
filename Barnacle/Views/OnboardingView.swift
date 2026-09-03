import SwiftUI
import SwiftData

/// First-run onboarding (spec `09`): the three decisions the app actually depends on — what
/// role, which countries, which companies — asked once, in order.
///
/// **Onboarding owns no state.** Steps 1 and 2 write straight into the same `ScrapePreferences`
/// object `SettingsView` edits (spec `07`), and step 3 opens the same add-company modal the
/// Feed's `+` opens (spec `08`). The only thing this view keeps is which step is on screen and
/// whether that modal is up. If it ever needs a model of its own, something has been duplicated.
struct OnboardingView: View {
    /// Set once the flow has been seen. `RootView` presents onboarding while this is absent or
    /// false; Settings' "Show onboarding again" clears it.
    static let completedKey = "onboarding.completed"

    @Environment(ScrapePreferences.self) private var preferences
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(\.dismiss) private var dismiss

    /// Step 3's list: the companies added so far, which is also every company the app tracks.
    @Query(sort: \Company.name) private var companies: [Company]

    @AppStorage(OnboardingView.completedKey) private var hasCompletedOnboarding = false

    @State private var step = Step.role
    @State private var isAddingCompany = false

    private enum Step: Int, CaseIterable, Identifiable {
        case role
        case countries
        case companies

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .role: "What are you looking for?"
            case .countries: "Where would you work?"
            case .companies: "Which companies are you tracking?"
            }
        }

        /// The last step finishes rather than advancing.
        var next: Step? { Step(rawValue: rawValue + 1) }

        var forwardTitle: String { next == nil ? "Done" : "Continue" }
    }

    /// Zero countries is the one state a step blocks on: spec `09` wants at least one before
    /// Continue enables. Nothing else here can be wrong — a role level is always set, and step 3
    /// is finishable with no companies at all.
    private var canGoForward: Bool {
        step != .countries || !preferences.countries.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            Text(step.title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Hairline()

            content
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)

            Hairline()

            footer
        }
        .padding(Theme.Metrics.screenPadding)
        .frame(width: 460)
        .background(Theme.Palette.surface)
        // A sheet is its own window, so it doesn't inherit the main window's pinned appearance
        // — same light-only caveat as `RootView`.
        .preferredColorScheme(.light)
        // The same modal the Feed's `+` opens, so the name probe, the checker, and the role
        // counts are all the shipped ones (spec `08`).
        .sheet(isPresented: $isAddingCompany) {
            AddCompanyView()
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .role: roleStep
        case .countries: countryStep
        case .companies: companyStep
        }
    }

    /// Step 1. The sentence underneath is doing real work: it says this is a durable setting
    /// rather than a filter, which is the whole premise of spec `07`.
    private var roleStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoleLevelSelector(selection: preferences.roleLevel) { level in
                preferences.roleLevel = level
            }

            Text("You can change this in Settings when you graduate.")
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    /// Step 2. The same picker and the same switch Settings shows, writing to the same object.
    private var countryStep: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            CountrySelector(selection: preferences.countries) { codes in
                preferences.countries = codes
            }

            if preferences.countries.isEmpty {
                Text("Pick at least one country to carry on.")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.Palette.accent)
            }

            UnknownLocationToggle(preferences: preferences)
        }
    }

    /// Step 3. Adding is the modal's job; this step is the button that opens it and the list of
    /// what came back. The modal's role counts run against the settings just chosen, so the user
    /// sees the consequence of steps 1 and 2 immediately.
    private var companyStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button("Add a company") { isAddingCompany = true }
                    .buttonStyle(.barnacleSecondary)

                Text("Type a name \u{2014} Barnacle looks for its job board.")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            if companies.isEmpty {
                Text("You can finish without any and add them later with the + on the Feed.")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(companies) { company in
                            CompactRow(title: company.name, metadata: company.atsType.displayName)
                            Hairline()
                        }
                    }
                }
                .frame(maxHeight: 132)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                }
            }
        }
    }

    // MARK: - Chrome

    private var footer: some View {
        HStack(spacing: 8) {
            StepIndicator(current: step.rawValue, count: Step.allCases.count)

            Spacer(minLength: 8)

            // Skipping keeps whatever is set, which on an untouched flow is the defaults:
            // internships, US + Canada, unknown locations included. Never half-configured.
            Button("Skip") { complete() }
                .buttonStyle(.barnacleSecondary)

            Button(step.forwardTitle) {
                if let next = step.next {
                    step = next
                } else {
                    complete()
                }
            }
            .buttonStyle(.barnaclePrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(!canGoForward)
        }
    }

    /// Marks the flow seen, closes it, and scrapes — the payoff for step 3 is postings showing up
    /// rather than an empty feed until the next scheduled run.
    private func complete() {
        hasCompletedOnboarding = true
        dismiss()
        Task { await scrapeCoordinator.refreshNow() }
    }
}

/// Three dots, not a progress bar: three steps don't need a percentage (spec `09`).
private struct StepIndicator: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Theme.Palette.accent : Theme.Palette.hairline)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
        .environment(ScrapePreferences())
        .environment(ScrapeCoordinator(container: BarnacleStore.makeContainer(inMemory: true)))
}
