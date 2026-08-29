import SwiftUI

/// Screen chrome: an 18pt serif title over a hairline, with room for a controls row on the
/// trailing edge (the Feed's company filter and sort toggle land there in spec `02`).
struct ScreenHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Spacer(minLength: 8)

                trailing()
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 10)

            Hairline()
        }
        .background(Theme.Palette.background)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

#Preview("Screen header") {
    VStack(spacing: 0) {
        ScreenHeader(title: "Feed") {
            HStack(spacing: 6) {
                Button("All companies") {}.buttonStyle(.quietControl())
                Button("Newest") {}.buttonStyle(.quietControl(isActive: true))
            }
        }
        Spacer()
    }
    .frame(width: 480, height: 160)
    .screenBackground()
}
