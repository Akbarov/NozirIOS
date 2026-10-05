import SwiftUI

/// Every sentence a parent reads, in one language. The sentences themselves
/// are generated from the Android app's strings (`L10n.generated.swift`).
public struct L10n: Sendable, Equatable {
    public let language: AppLanguage

    public init(_ language: AppLanguage) {
        self.language = language
    }
}

private struct L10nKey: EnvironmentKey {
    static let defaultValue = L10n(.uz)
}

public extension EnvironmentValues {
    /// Set once at the root from `LanguageStore`; every view reads its text here.
    var l10n: L10n {
        get { self[L10nKey.self] }
        set { self[L10nKey.self] = newValue }
    }
}
