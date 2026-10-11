import Foundation
import SQLite3

/// Reads one value from a key/value SQLite table (VS Code style `ItemTable`) without writing anything.
public enum SQLiteValueReader {
    public enum ReadError: Error, Equatable, Sendable {
        case openFailed
        case queryFailed
    }

    public static func value(forKey key: String, table: String = "ItemTable", in url: URL) throws(ReadError) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw .openFailed
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM \(table) WHERE key = ?1 LIMIT 1", -1, &statement, nil)
            == SQLITE_OK
        else { throw .queryFailed }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            let count = Int(sqlite3_column_bytes(statement, 0))
            let data = Data(bytes: bytes, count: count)
            return String(data: data, encoding: .utf8)
        case SQLITE_DONE:
            return nil
        default:
            throw .queryFailed
        }
    }
}
