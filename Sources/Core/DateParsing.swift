import Foundation

public enum DateParsing {
    /// Parses ISO 8601 timestamps with 0 to 9 fractional digits and `Z` or `±hh:mm` offsets,
    /// e.g. `2026-10-11T02:00:00.419134+00:00` or `2026-10-23T13:16:38.000Z`.
    public static func iso8601(_ string: String) -> Date? {
        var text = string.trimmingCharacters(in: .whitespaces)
        var fraction: Double = 0

        if let dot = text.firstIndex(of: ".") {
            let afterDot = text.index(after: dot)
            let digitsEnd = text[afterDot...].firstIndex { !$0.isNumber } ?? text.endIndex
            let digits = text[afterDot..<digitsEnd]
            if !digits.isEmpty, let value = Double("0." + digits) {
                fraction = value
            }
            text.removeSubrange(dot..<digitsEnd)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: text) else { return nil }
        return date.addingTimeInterval(fraction)
    }

    /// Unix epoch in seconds, or milliseconds when the value is too large to be seconds.
    public static func epoch(_ value: Double) -> Date {
        value > 100_000_000_000 ? Date(timeIntervalSince1970: value / 1000) : Date(timeIntervalSince1970: value)
    }

    /// A `JSONDecoder` that understands both ISO 8601 strings and epoch numbers.
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                return epoch(number)
            }
            let string = try container.decode(String.self)
            if let date = iso8601(string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
        }
        return decoder
    }
}
