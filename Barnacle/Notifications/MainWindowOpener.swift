import SwiftUI

extension View {
    /// Hands the notifier a way to reopen the main window.
    ///
    /// `openWindow` is only reachable from a `View`, but the captured action keeps working after
    /// the window is gone — which is exactly the case that matters here, since closing the window
    /// leaves Barnacle running in the menu bar (§8) and a clicked notification still has to bring
    /// the Feed back.
    func registersMainWindowOpener(with service: NotificationService) -> some View {
        modifier(MainWindowOpenerRegistration(service: service))
    }
}

private struct MainWindowOpenerRegistration: ViewModifier {
    let service: NotificationService

    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            service.registerMainWindowOpener { openWindow(id: BarnacleWindow.main) }
        }
    }
}
