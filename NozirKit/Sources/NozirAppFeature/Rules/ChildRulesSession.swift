import Foundation
import Observation
import NozirFamily

/// What a rules screen says after a save.
enum RuleNotice: Equatable, Sendable {
    case saved
    /// Changed elsewhere since it was read: the latest is shown, the edit is dropped.
    case conflict
}

/// How one rule write ended.
enum RuleSaveOutcome: Equatable, Sendable {
    case saved
    /// Refused as stale. The session has read the rules again; nothing was resent.
    case conflict
    case failed(UserMessage)
    /// The task was cancelled (the screen went away): nothing to say.
    case cancelled
}

/// One child's rule set, shared by P09 and every screen opened from it.
///
/// The server keeps one version for all of a child's rules, and every write
/// moves it. The screens therefore write against this session's version and
/// hand every answer back here: a save on P10 then never makes P09's next save
/// look stale. Each screen keeps only its own edit.
@MainActor
@Observable
final class ChildRulesSession {
    let childId: UUID
    let childName: String?
    let family: FamilyStore
    private(set) var snapshot: RuleSnapshot?
    private(set) var isLoading = false
    /// The first read failed: there is nothing to show yet.
    private(set) var loadFailure: UserMessage?
    /// A later read found no connection; what is shown is the last known state.
    private(set) var isOffline = false
    /// A free family keeps another child active: these rules cannot change.
    private(set) var isFrozen = false
    private(set) var isMakingActive = false
    /// A write of this hub is on its way. Every screen of the hub holds its
    /// Save back meanwhile: two writes against one version would make this
    /// phone's own save look like another phone's (spec D2).
    private(set) var isWriting = false
    /// Why "make this child active" did not work.
    private(set) var message: UserMessage?
    /// Goes up with every read and every accepted answer; an older read is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var planGeneration = 0
    @ObservationIgnored private var writesInFlight = 0

    init(childId: UUID, family: FamilyStore) {
        self.childId = childId
        self.family = family
        childName = family.child(childId)?.displayName
    }

    var version: Int64? {
        snapshot?.version
    }

    /// Reads once. A tab switch or a screen opened again leaves what is held alone.
    func load() async {
        guard snapshot == nil, !isLoading else { return }
        await read()
    }

    /// Reads whatever is held again: after a conflict, or a pull to refresh.
    func reload() async {
        await read()
    }

    /// A write's answer. One older than what is held is ignored (two screens'
    /// answers can land out of order), and a read still in flight is dropped:
    /// it was asked before this write landed.
    func accept(_ fresh: RuleSnapshot) {
        if let snapshot, fresh.version < snapshot.version { return }
        generation += 1
        isLoading = false
        snapshot = fresh
        loadFailure = nil
        isOffline = false
    }

    /// P12's answer carries only the version and the ceiling; the rest is as held.
    func acceptBonus(version: Int64, ceiling: Int) {
        guard let snapshot else { return }
        accept(RuleSnapshot(
            version: version,
            screenTime: ScreenTimeLimit(
                schoolDayMinutes: snapshot.screenTime.schoolDayMinutes,
                weekendMinutes: snapshot.screenTime.weekendMinutes,
                maxDailyBonusMinutes: ceiling
            ),
            bedtime: snapshot.bedtime,
            locationTracking: snapshot.locationTracking,
            maxTrustBonusMinutes: snapshot.maxTrustBonusMinutes
        ))
    }

    /// Sends one write and keeps its answer. A conflict reads the rules again
    /// and is never resent on the parent's behalf (openapi `RuleVersionConflict`).
    func write(_ send: () async throws -> RuleSnapshot) async -> RuleSaveOutcome {
        await tracking {
            do {
                accept(try await send())
                return .saved
            } catch is CancellationError {
                return .cancelled
            } catch {
                let failure = UserMessage(error)
                guard failure == .conflict else { return .failed(failure) }
                await reload()
                return .conflict
            }
        }
    }

    /// Counts `work` as a write of this hub for as long as it runs: a save made
    /// of several calls (P09's two, P12's re-read and write) stays one.
    func tracking<T>(_ work: () async throws -> T) async rethrows -> T {
        writesInFlight += 1
        isWriting = true
        defer {
            writesInFlight -= 1
            isWriting = writesInFlight > 0
        }
        return try await work()
    }

    func makeActive() async {
        guard !isMakingActive else { return }
        isMakingActive = true
        message = nil
        defer { isMakingActive = false }
        planGeneration += 1
        do {
            let subscription = try await family.service.chooseActiveChild(childId)
            // A plan read asked before this answer would freeze the child again.
            planGeneration += 1
            isFrozen = !subscription.isChildActive(childId)
        } catch is CancellationError {
            return
        } catch {
            message = UserMessage(error)
        }
    }

    private func read() async {
        generation += 1
        let mine = generation
        isLoading = true
        // Retry after a failed first read: the spinner, not the old error.
        if snapshot == nil { loadFailure = nil }
        do {
            let fresh = try await family.service.rules(of: childId)
            guard mine == generation else { return }
            snapshot = fresh
            loadFailure = nil
            isOffline = false
        } catch is CancellationError {
            if mine == generation { isLoading = false }
            return
        } catch {
            guard mine == generation else { return }
            let failure = UserMessage(error)
            if snapshot == nil {
                loadFailure = failure
            } else if failure == .noConnection || failure == .timeout {
                isOffline = true
            }
        }
        isLoading = false
        await readPlan()
    }

    /// An unknown plan freezes nobody (Android `FamilyPlan.Unknown`): a lock
    /// drawn because an answer had not arrived would tell a paying family they
    /// had lost a child.
    private func readPlan() async {
        planGeneration += 1
        let mine = planGeneration
        guard let subscription = try? await family.service.subscription(), mine == planGeneration else { return }
        isFrozen = !subscription.isChildActive(childId)
    }
}

/// A session is one hub's: two sessions for the same child are still two.
extension ChildRulesSession: Hashable {
    nonisolated static func == (lhs: ChildRulesSession, rhs: ChildRulesSession) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
