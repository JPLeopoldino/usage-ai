import os

/// Logs carry phases, status codes and durations only — never tokens, cookies, emails or bodies.
public enum Log {
    static let subsystem = "io.github.jpleopoldino.UsageAI"

    public static let store = Logger(subsystem: subsystem, category: "store")
    public static let scheduler = Logger(subsystem: subsystem, category: "scheduler")

    public static func provider(_ id: ProviderID) -> Logger {
        Logger(subsystem: subsystem, category: id.rawValue)
    }
}
