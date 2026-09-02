import SwiftUI

/// What the `⌘J` panel shows (spec `05`): the shared application form on a floating card.
///
/// Deliberately thin — every field, every rule about what's required, and the save itself live
/// in `ApplicationFormView`, so the overlay and the Applied tab's sheet cannot drift apart.
struct QuickAddView: View {
    var onCancel: () -> Void
    var onSaved: () -> Void

    @State private var model = ApplicationFormModel()

    var body: some View {
        ApplicationFormView(model: model, onCancel: onCancel, onSaved: onSaved)
            .surfaceCard()
            // Esc from anywhere in the card, not just the Cancel button's key equivalent.
            .onExitCommand(perform: onCancel)
            // The panel is its own window and the palette is fixed light values — the same
            // light-only caveat as `RootView`.
            .preferredColorScheme(.light)
    }
}

#Preview("Quick add") {
    QuickAddView(onCancel: {}, onSaved: {})
        .frame(width: 420)
        .padding(16)
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
}
