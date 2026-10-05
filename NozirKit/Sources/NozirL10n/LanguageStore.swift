import Foundation
import Observation

/// The language the parent chose in the app (P21), or the phone's if they
/// have not chosen. Views re-render when it changes because they read `l10n`.
@MainActor
@Observable
public final class LanguageStore {
    static let key = "nozir.appLanguage"

    public private(set) var current: AppLanguage
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        if let saved = defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) {
            current = saved
        } else {
            current = AppLanguage.preferred(from: preferredLanguages)
        }
    }

    public var l10n: L10n {
        L10n(current)
    }

    public func set(_ language: AppLanguage) {
        current = language
        defaults.set(language.rawValue, forKey: Self.key)
    }
}
