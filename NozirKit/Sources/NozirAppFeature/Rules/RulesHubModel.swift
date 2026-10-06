import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P09's frame: which child, and that child's session and limit model.
/// From Profile the parent may move between children (2+); from P03 it is
/// that child only.
@MainActor
@Observable
final class RulesHubModel {
    let picksChild: Bool
    let family: FamilyStore
    private(set) var session: ChildRulesSession?
    private(set) var dailyLimit: DailyLimitModel?
    private let makeSession: @MainActor (UUID) -> ChildRulesSession
    private let makeDailyLimit: @MainActor (ChildRulesSession) -> DailyLimitModel

    /// `childId` nil opens on the first child.
    init(
        childId: UUID?,
        picksChild: Bool,
        family: FamilyStore,
        makeSession: @escaping @MainActor (UUID) -> ChildRulesSession,
        makeDailyLimit: @escaping @MainActor (ChildRulesSession) -> DailyLimitModel
    ) {
        self.picksChild = picksChild
        self.family = family
        self.makeSession = makeSession
        self.makeDailyLimit = makeDailyLimit
        select(childId ?? family.children.first?.id)
    }

    var selectedChildId: UUID? {
        session?.childId
    }

    var showsSwitcher: Bool {
        picksChild && family.children.count > 1
    }

    /// Another child is another rule set: a new session, so nothing of the
    /// previous child's — its rules, an edit, an answer still on its way — can
    /// reach this one. The same child again keeps everything.
    func select(_ childId: UUID?) {
        guard let childId, childId != session?.childId else { return }
        let fresh = makeSession(childId)
        session = fresh
        dailyLimit = makeDailyLimit(fresh)
    }

    func load() async {
        await dailyLimit?.load()
    }

    /// Pull to refresh. Nothing while a save is in flight: a newer version read
    /// mid-save would be the one the save's next step writes against.
    func refresh() async {
        guard let session, !session.isWriting, !(dailyLimit?.isSaving ?? false) else { return }
        await session.reload()
    }

    func switcherChildren(_ l10n: L10n) -> [NozirSwitcherChild] {
        family.children.enumerated().map { position, child in
            NozirSwitcherChild(
                id: child.id,
                name: child.displayName,
                tone: .forKey(child.avatarKey, position: position),
                accessibilityLabel: l10n.contentDescriptionChildAvatar(child.displayName)
            )
        }
    }
}
