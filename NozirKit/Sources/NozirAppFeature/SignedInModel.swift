import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// Everything the signed-in app shares for one session: the family, the tab,
/// and whether the add-a-child flow is up. A new sign-in gets a new one, so a
/// signed-out parent's children never linger in memory.
@MainActor
@Observable
public final class SignedInModel {
    public enum Tab: Hashable, Sendable {
        case home, profile
    }

    public var tab: Tab = .home
    public var isAddingChild = false
    public let family: FamilyStore

    private let language: LanguageStore
    private let appearance: AppearanceStore
    private let localeSync: LocaleSync
    private let signOutAction: @MainActor () async -> Void
    @ObservationIgnored private var hasStarted = false

    init(
        family: FamilyStore,
        language: LanguageStore,
        appearance: AppearanceStore,
        localeSync: LocaleSync,
        signOut: @escaping @MainActor () async -> Void
    ) {
        self.family = family
        self.language = language
        self.appearance = appearance
        self.localeSync = localeSync
        signOutAction = signOut
    }

    /// After sign-in: a family with no children goes straight to adding one
    /// (on iOS `isNewAccount` is always false, so the list decides). A list that
    /// cannot be loaded opens nothing and is asked for again next time.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await localeSync.resumeIfNeeded()
        do {
            try await family.refresh()
            if family.children.isEmpty {
                isAddingChild = true
            }
        } catch {
            hasStarted = false
        }
    }

    public func presentAddChild() {
        isAddingChild = true
    }

    public func finishAddChild() {
        isAddingChild = false
        tab = .home
    }

    func makeProfileModel() -> ProfileModel {
        ProfileModel(family: family, language: language, appearance: appearance, localeSync: localeSync, signOut: signOutAction)
    }

    func makeAddChildModel() -> AddChildModel {
        AddChildModel()
    }

    func makeRulesModel(_ draft: ChildDraft) -> NewChildRulesModel {
        NewChildRulesModel(draft: draft, family: family)
    }

    func makePairingModel(_ child: Child) -> PairingModel {
        PairingModel(child: child, family: family)
    }

    func makeDetailsModel(_ child: Child) -> ChildDetailsModel {
        ChildDetailsModel(child: child, family: family)
    }
}
