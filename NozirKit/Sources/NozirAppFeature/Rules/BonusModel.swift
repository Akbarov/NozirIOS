import Foundation
import Observation
import NozirFamily

/// P12 (Android `BonusViewModel`): the daily ceiling and which tasks are on.
/// The ceiling lives in the rule set, so the whole configuration is written
/// against the session's version and the answer moves the session.
@MainActor
@Observable
final class BonusModel {
    let session: ChildRulesSession
    /// The configuration as the server last stated it.
    private(set) var saved: BonusConfig?
    /// The parent's edit on top; nil while nothing has been touched.
    private(set) var edited: BonusConfig?
    private(set) var isLoading = false
    private(set) var loadFailure: UserMessage?
    private(set) var isSaving = false
    private(set) var message: UserMessage?
    private(set) var notice: RuleNotice?

    init(session: ChildRulesSession) {
        self.session = session
    }

    var config: BonusConfig? {
        edited ?? saved
    }

    /// A kind this app has no name for is kept and sent back, but not drawn.
    var visibleChallenges: [BonusChallenge] {
        (config?.challenges ?? []).filter { challenge in
            if case .unknown = challenge.kind { return false }
            return true
        }
    }

    var canSave: Bool {
        guard !isSaving, !session.isWriting, !session.isFrozen, session.version != nil, let edited else { return false }
        return edited != saved
    }

    /// Reads once: a tab switch must not throw an edit away.
    func load() async {
        await session.load()
        guard saved == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await session.family.service.bonus(of: session.childId)
            saved = fresh
            loadFailure = nil
            // Newer than the session: the save would be refused as stale. Read the session again.
            if let version = session.version, fresh.ruleVersion > version {
                await session.reload()
            }
        } catch is CancellationError {
            return
        } catch {
            loadFailure = UserMessage(error)
        }
    }

    func setCeiling(_ minutes: Int) {
        edit { $0.maxDailyBonusMinutes = minutes }
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        edit { $0 = $0.withChallenge(id, enabled: enabled) }
    }

    /// One call for the ceiling and the tasks: sent apart, the child's phone
    /// would see a moment where a task pays above a ceiling just lowered.
    func save() async {
        guard canSave, let edited, let version = session.version else { return }
        isSaving = true
        message = nil
        notice = nil
        defer { isSaving = false }
        // The re-read and the write are one write of the hub.
        await session.tracking { await send(edited, version: version) }
    }

    private func send(_ edited: BonusConfig, version: Int64) async {
        let service = session.family.service
        let childId = session.childId
        // The session moved past what was read (a refresh, or another phone):
        // read the config again, and never write over a change made elsewhere.
        if let held = saved, held.ruleVersion != version {
            do {
                let fresh = try await service.bonus(of: childId)
                let changedElsewhere = Self.differs(fresh, from: held)
                saved = fresh
                if changedElsewhere {
                    self.edited = nil
                    notice = .conflict
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                message = UserMessage(error)
                return
            }
        }
        do {
            let answer = try await service.setBonus(edited, of: childId, version: version)
            session.acceptBonus(version: answer.ruleVersion, ceiling: answer.maxDailyBonusMinutes)
            saved = answer
            self.edited = nil
            notice = .saved
        } catch is CancellationError {
            return
        } catch {
            let failure = UserMessage(error)
            guard failure == .conflict else {
                message = failure
                return
            }
            // The rules moved under this screen: drop the edit, read both again, never resend.
            self.edited = nil
            await session.reload()
            do {
                saved = try await service.bonus(of: childId)
                notice = .conflict
            } catch is CancellationError {
                saved = nil
            } catch {
                // No fresh base: show the load failure with Retry rather than keep a stale one.
                saved = nil
                loadFailure = UserMessage(error)
            }
        }
    }

    /// The ceiling or any task's switch (matched by id) differs.
    private static func differs(_ fresh: BonusConfig, from held: BonusConfig) -> Bool {
        if fresh.maxDailyBonusMinutes != held.maxDailyBonusMinutes { return true }
        let heldEnabled = Dictionary(held.challenges.map { ($0.id, $0.enabled) }, uniquingKeysWith: { first, _ in first })
        let freshEnabled = Dictionary(fresh.challenges.map { ($0.id, $0.enabled) }, uniquingKeysWith: { first, _ in first })
        return heldEnabled != freshEnabled
    }

    private func edit(_ change: (inout BonusConfig) -> Void) {
        guard var copy = config else { return }
        change(&copy)
        edited = copy
        notice = nil
        message = nil
    }
}
