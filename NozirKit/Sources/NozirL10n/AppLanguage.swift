/// The languages Nozir speaks, in the order the language picker lists them.
public enum AppLanguage: String, CaseIterable, Sendable {
    case uz, ru, en

    /// The phone's first preferred language if Nozir speaks it, Uzbek otherwise.
    /// Only the first: a parent whose phone is in German and then English has
    /// not asked for English.
    public static func preferred(from identifiers: [String]) -> AppLanguage {
        guard let first = identifiers.first else { return .uz }
        let code = first.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { $0.lowercased() } ?? ""
        return AppLanguage(rawValue: code) ?? .uz
    }
}
