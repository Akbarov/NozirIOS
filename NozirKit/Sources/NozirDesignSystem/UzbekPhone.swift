/// A +998 number as a parent types and reads it: the country code is fixed on
/// screen, so the field holds the nine subscriber digits only.
public enum UzbekPhone {
    public static let subscriberDigits = 9

    /// The subscriber digits in whatever was typed or pasted. A whole number
    /// ("+998 90 123-45-67", or autofill's "+998901234567") loses its country code.
    public static func digits(from input: String) -> String {
        var digits = input.filter { $0.isASCII && $0.isNumber }
        if digits.count == 12, digits.hasPrefix("998") {
            digits.removeFirst(3)
        }
        return String(digits.prefix(subscriberDigits))
    }

    /// "901234567" → "90 123 45 67"; a partial number is grouped as far as it goes.
    public static func grouped(_ digits: String) -> String {
        var parts: [String] = []
        var rest = Substring(digits)
        for size in [2, 3, 2, 2] where !rest.isEmpty {
            parts.append(String(rest.prefix(size)))
            rest = rest.dropFirst(size)
        }
        return parts.joined(separator: " ")
    }

    /// The server's form, or nil while the number is incomplete.
    public static func e164(_ digits: String) -> String? {
        digits.count == subscriberDigits ? "+998" + digits : nil
    }

    public static func digits(fromE164 number: String?) -> String {
        guard let number, number.hasPrefix("+998") else { return "" }
        return digits(from: String(number.dropFirst(4)))
    }

    /// "+998901234567" → "+998 90 123 45 67". Anything else is shown as it is.
    public static func display(_ number: String) -> String {
        let digits = digits(fromE164: number)
        return digits.count == subscriberDigits ? "+998 " + grouped(digits) : number
    }
}
