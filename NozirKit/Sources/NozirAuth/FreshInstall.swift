import Foundation

/// Reinstalling the app signs the parent out (product decision, 2026-10-03).
///
/// Keychain items survive an uninstall; UserDefaults do not. A session found
/// before this install has ever marked itself therefore belongs to a previous
/// install and is dropped. Call once at launch, before anything reads the store.
public enum FreshInstall {
    private static let marker = "nozir.installMarker"

    public static func clearSessionLeftByPreviousInstall(store: any TokenStore, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: marker) else { return }
        store.clear()
        defaults.set(true, forKey: marker)
    }
}
