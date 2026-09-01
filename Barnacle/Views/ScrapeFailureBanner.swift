import SwiftUI

/// Surfaces `ScrapeRun.failures` (spec `01`), which nothing read until now.
///
/// A company whose board has moved fails on every run and stores nothing — Greenhouse and Lever
/// both answer a dead token with a 404 — which on the Feed looks exactly like a company with no
/// open internships. Without this the two states render identically, so a company can sit broken
/// for days while the user reads the empty list as "nothing new yet."
///
/// Deliberately not dismissible: the condition is persistent, so the banner is too. It collapses
/// to one line instead, and offers the screen that can fix it.
struct ScrapeFailureBanner: View {
    let failures: [ScrapeFailure]
    let onManageCompanies: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow

            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(failures, id: \.companyName) { failure in
                        Text("\(failure.companyName) \u{2014} \(failure.message)")
                            .font(Theme.Typography.metadata)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.bottom, 8)
            }
        }
        .background(Theme.Palette.accentTint)
        .overlay(alignment: .bottom) { Hairline() }
        .animation(Theme.Metrics.hoverAnimation, value: isExpanded)
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Palette.accent)

            Text(summaryText)
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.textSecondary)

            Spacer(minLength: 8)

            Button(isExpanded ? "Hide" : "Details") {
                isExpanded.toggle()
            }
            .buttonStyle(.quietControl(isActive: isExpanded))

            Button("Manage companies", action: onManageCompanies)
                .buttonStyle(.quietControl())
        }
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .padding(.vertical, 6)
    }

    private var summaryText: String {
        failures.count == 1
            ? "\(failures[0].companyName) couldn\u{2019}t be checked"
            : "\(failures.count) companies couldn\u{2019}t be checked"
    }
}

#Preview("One failure") {
    ScrapeFailureBanner(
        failures: [
            ScrapeFailure(
                companyName: "Notion",
                message: "HTTP 404 from https://boards-api.greenhouse.io/v1/boards/notion/jobs?content=true."
            )
        ],
        onManageCompanies: {}
    )
    .frame(width: 720)
    .screenBackground()
}

#Preview("Several failures") {
    ScrapeFailureBanner(
        failures: [
            ScrapeFailure(companyName: "Notion", message: "HTTP 404 from https://boards-api.greenhouse.io/v1/boards/notion/jobs?content=true."),
            ScrapeFailure(companyName: "Ramp", message: "HTTP 404 from https://api.lever.co/v0/postings/ramp?mode=json."),
            ScrapeFailure(companyName: "Anthropic", message: "No SmartRecruiters adapter yet.")
        ],
        onManageCompanies: {}
    )
    .frame(width: 720)
    .screenBackground()
}
