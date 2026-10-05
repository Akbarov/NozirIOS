import Foundation
import NozirL10n

/// The parent's language choice: on screen at once, on the server when it can
/// be (the server writes AI summaries and notifications in it). A choice the
/// server missed is sent again the next time the app starts signed in.
@MainActor
final class LocaleSync {
    static let unsentKey = "nozir.appLanguage.unsent"

    private let store: LanguageStore
    private let defaults: UserDefaults
    private let send: @Sendable (String) async throws -> Void

    init(store: LanguageStore, defaults: UserDefaults = .standard, send: @escaping @Sendable (String) async throws -> Void) {
        self.store = store
        self.defaults = defaults
        self.send = send
    }

    func choose(_ language: AppLanguage) async {
        store.set(language)
        defaults.set(true, forKey: Self.unsentKey)
        await push(language)
    }

    func resumeIfNeeded() async {
        guard defaults.bool(forKey: Self.unsentKey) else { return }
        await push(store.current)
    }

    private func push(_ language: AppLanguage) async {
        do {
            try await send(language.rawValue)
            // A newer choice made meanwhile keeps the mark until it is sent too.
            if store.current == language {
                defaults.removeObject(forKey: Self.unsentKey)
            }
        } catch {
            // Kept for the next start; the screen already speaks the new language.
        }
    }
}
