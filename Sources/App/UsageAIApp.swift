import SwiftUI
import UsageCore

@main
struct UsageAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView()
                .environment(environment)
                .environment(environment.store)
                .environment(environment.settings)
        } label: {
            MenuBarLabel(store: environment.store, settings: environment.settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(environment)
                .environment(environment.store)
                .environment(environment.settings)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ScreenshotRenderer.runIfRequested() { return }
        #endif
        AppEnvironment.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.shared.stop()
    }
}
