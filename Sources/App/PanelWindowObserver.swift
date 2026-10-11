import AppKit
import SwiftUI

/// Reports each time the menu bar panel opens. `MenuBarExtra` has no callback for it, and
/// `onAppear` only fires the first time, so watch the panel window becoming key instead.
struct PanelWindowObserver: NSViewRepresentable {
    var onOpen: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        ObserverView(onOpen: onOpen)
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onOpen = onOpen
    }

    final class ObserverView: NSView {
        var onOpen: () -> Void
        private var observer: NSObjectProtocol?

        init(onOpen: @escaping () -> Void) {
            self.onOpen = onOpen
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            guard let window else { return }
            MenuBarPanel.window = window
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onOpen() }
            }
            if window.isKeyWindow {
                onOpen()
            }
        }
    }
}

/// The menu bar panel's window, so code can close it: opening Settings from the panel
/// doesn't close the panel by itself.
enum MenuBarPanel {
    static weak var window: NSWindow?

    static func close() {
        window?.close()
    }
}
