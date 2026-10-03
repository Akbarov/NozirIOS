import Foundation

/// The server's instants: `2026-10-03T11:31:09Z`, with any number of
/// fractional digits and either `Z` or a `±hh:mm` offset.
///
/// `ISO8601DateFormatter` is asked only for the whole-second part; the fraction
/// is cut out and added back, because how many digits the formatter accepts is
/// not something this code should depend on.
enum RFC3339 {
    static func date(from text: String) -> Date? {
        var wholeSecondText = text
        var fraction: Double = 0
        if let dot = text.firstIndex(of: ".") {
            let afterDot = text[text.index(after: dot)...]
            let digits = afterDot.prefix(while: { $0.isASCII && $0.isNumber })
            guard !digits.isEmpty, let value = Double("0." + digits) else { return nil }
            fraction = value
            wholeSecondText = String(text[..<dot]) + String(afterDot.dropFirst(digits.count))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let whole = formatter.date(from: wholeSecondText) else { return nil }
        return whole.addingTimeInterval(fraction)
    }
}
