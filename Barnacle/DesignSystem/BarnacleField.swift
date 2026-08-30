import SwiftUI

/// The label above a form field: quiet, 11pt, secondary.
struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.Typography.metadata)
            .foregroundStyle(Theme.Palette.textSecondary)
    }
}

extension View {
    /// Text-field chrome for the add-company modal (`03`) and the `⌘J` overlay (`05`): surface
    /// fill, hairline border that picks up the accent on focus, 12pt text.
    ///
    /// Pass the field's `@FocusState` value — a `TextFieldStyle` can't read focus itself, and
    /// spec `06` wants the accent reserved for active states.
    func barnacleField(isFocused: Bool = false) -> some View {
        self
            .textFieldStyle(.plain)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
                    .strokeBorder(isFocused ? Theme.Palette.accent : Theme.Palette.hairline, lineWidth: 1)
            }
            .animation(Theme.Metrics.hoverAnimation, value: isFocused)
    }
}

#Preview("Fields") {
    struct Host: View {
        @State private var name = "Stripe"
        @State private var url = ""
        @FocusState private var isURLFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    FieldLabel("Company name")
                    TextField("Acme", text: $name)
                        .barnacleField()
                }
                VStack(alignment: .leading, spacing: 4) {
                    FieldLabel("Careers URL")
                    TextField("boards.greenhouse.io/acme", text: $url)
                        .barnacleField(isFocused: isURLFocused)
                        .focused($isURLFocused)
                }
            }
            .frame(width: 300)
            .surfaceCard()
            .padding(24)
            .screenBackground()
        }
    }

    return Host()
}
