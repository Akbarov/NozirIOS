import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P21 (Android `ProfileViewModel`): the parent, the children with their
/// pairing state, theme, language, sign-out.
@MainActor
@Observable
public final class ProfileModel {
    public private(set) var parent: ParentProfile?
    public private(set) var message: UserMessage?
    public private(set) var isSigningOut = false
    public let family: FamilyStore
    public let language: LanguageStore
    public let appearance: AppearanceStore

    private let localeSync: LocaleSync
    private let currentYear: Int
    private let signOutAction: @MainActor () async -> Void

    init(
        family: FamilyStore,
        language: LanguageStore,
        appearance: AppearanceStore,
        localeSync: LocaleSync,
        currentYear: Int = Calendar.current.component(.year, from: Date()),
        signOut: @escaping @MainActor () async -> Void
    ) {
        self.family = family
        self.language = language
        self.appearance = appearance
        self.localeSync = localeSync
        self.currentYear = currentYear
        signOutAction = signOut
    }

    public func load() async {
        message = nil
        if let me = try? await family.service.me() {
            parent = me
        }
        do {
            try await family.refresh()
        } catch {
            message = UserMessage(error)
        }
    }

    public func choose(_ language: AppLanguage) async {
        await localeSync.choose(language)
    }

    public func choose(_ mode: AppearanceMode) {
        appearance.set(mode)
    }

    public func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await signOutAction()
    }

    public func displayName(_ l10n: L10n) -> String {
        let name = parent?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? l10n.profileNoName : name
    }

    public var phone: String? {
        parent?.phoneE164.map(UzbekPhone.display)
    }

    /// Android `profile_child_name_and_age`: this year minus the birth year.
    public func age(of child: Child) -> Int {
        currentYear - child.birthYear
    }

    /// Android `ProfileChildStatus`.
    public static func status(of state: PairingState, _ l10n: L10n) -> (label: String, level: NozirStatusLevel) {
        switch state {
        case .paired: (l10n.profileChildStatePaired, .good)
        case .appInstalled: (l10n.profileChildStateAppInstalled, .attention)
        case .codeIssued: (l10n.profileChildStateCodeIssued, .attention)
        case .notPaired: (l10n.profileChildStateNotPaired, .action)
        }
    }
}
