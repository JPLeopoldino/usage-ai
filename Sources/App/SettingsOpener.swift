import AppKit
import SwiftUI

/// Opens the Settings window in front of other apps.
///
/// A menu bar-only app (`LSUIElement`) isn't active when its menu is open, so `openSettings()`
/// alone puts the window behind the frontmost app. Becoming a regular app for as long as the
/// window is open fixes that; `AppEnvironment` switches back when it closes.
enum SettingsOpener {
    enum Tab: String {
        case general
        case accounts
        case about
    }

    static let tabDefaultsKey = "settingsTab"

    static func open(_ openSettings: OpenSettingsAction, tab: Tab? = nil) {
        if let tab {
            UserDefaults.standard.set(tab.rawValue, forKey: tabDefaultsKey)
        }
        MenuBarPanel.close()
        NSApp.setActivationPolicy(.regular)
        openSettings()
        activate()
        // The window may not exist yet on the first open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            activate()
            if let window = NSApp.windows.first(where: isSettingsWindow) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true
    }

    private static func activate() {
        // `activate()` doesn't bring an accessory app's windows forward, so keep the older call.
        NSApp.activate(ignoringOtherApps: true)
    }
}
