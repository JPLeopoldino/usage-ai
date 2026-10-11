import Foundation

public enum AppPaths {
    /// `~/Library/Application Support/UsageAI`. A fixed name so the Claude bridge script can find it.
    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/UsageAI", directoryHint: .isDirectory)
    }

    public static var claudeSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")
    }

    public static var cursorStateDatabase: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }
}
