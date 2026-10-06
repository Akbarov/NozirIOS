import Foundation
import Observation
import NozirFamily

/// P09's three numbers: the two day limits and the trust ladder's ceiling.
struct DailyLimitValues: Equatable, Sendable {
    var schoolDayMinutes: Int
    var weekendMinutes: Int
    var trustBonusMinutes: Int

    init(schoolDayMinutes: Int, weekendMinutes: Int, trustBonusMinutes: Int) {
        self.schoolDayMinutes = schoolDayMinutes
        self.weekendMinutes = weekendMinutes
        self.trustBonusMinutes = trustBonusMinutes
    }

    init(_ snapshot: RuleSnapshot) {
        self.init(
            schoolDayMinutes: snapshot.screenTime.schoolDayMinutes,
            weekendMinutes: snapshot.screenTime.weekendMinutes,
            trustBonusMinutes: snapshot.maxTrustBonusMinutes
        )
    }
}

/// P09 (Android `DailyLimitViewModel`): the daily limit and the trust ladder.
///
/// Only the parent's edit lives here; the rule as saved is the session's. A
/// load therefore never touches the edit, and a save made on another screen of
/// the same hub moves the version this one writes against.
@MainActor
@Observable
final class DailyLimitModel {
    let session: ChildRulesSession
    /// The edit; nil while nothing has been touched.
    private(set) var edited: DailyLimitValues?
    /// What the edit started from. A save checks it is still what the session holds.
    private(set) var editBase: DailyLimitValues?
    /// "Same every day" as the parent set it; nil reads it from the numbers.
    private(set) var sameEveryDayChoice: Bool?
    private(set) var isSaving = false
    private(set) var message: UserMessage?
    private(set) var notice: RuleNotice?

    init(session: ChildRulesSession) {
        self.session = session
    }

    var values: DailyLimitValues? {
        edited ?? session.snapshot.map(DailyLimitValues.init)
    }

    /// Not stored: the server and Android read it as school == weekend.
    var isSameEveryDay: Bool {
        if let sameEveryDayChoice { return sameEveryDayChoice }
        guard let values else { return true }
        return values.schoolDayMinutes == values.weekendMinutes
    }

    var hasLimitChange: Bool {
        guard let edited, let editBase else { return false }
        return edited.schoolDayMinutes != editBase.schoolDayMinutes || edited.weekendMinutes != editBase.weekendMinutes
    }

    var hasTrustLadderChange: Bool {
        guard let edited, let editBase else { return false }
        return edited.trustBonusMinutes != editBase.trustBonusMinutes
    }

    var canSave: Bool {
        !isSaving && !session.isFrozen && session.version != nil && (hasLimitChange || hasTrustLadderChange)
    }

    func load() async {
        await session.load()
    }

    func setSchoolDayMinutes(_ minutes: Int) {
        let same = isSameEveryDay
        edit { values in
            values.schoolDayMinutes = minutes
            if same { values.weekendMinutes = minutes }
        }
    }

    func setWeekendMinutes(_ minutes: Int) {
        edit { $0.weekendMinutes = minutes }
    }

    func setTrustBonusMinutes(_ minutes: Int) {
        edit { $0.trustBonusMinutes = minutes }
    }

    /// On gives the weekend the school-day figure, the one the parent was just
    /// looking at. Off changes nothing until a slider moves.
    func setSameEveryDay(_ isSame: Bool) {
        sameEveryDayChoice = isSame
        if isSame {
            edit { $0.weekendMinutes = $0.schoolDayMinutes }
        }
    }

    /// One button, up to two writes, in order: the ladder has an endpoint of its
    /// own. The limit then names the version the ladder came back with. A
    /// failure stops there: what was saved stays saved, and what was not waits
    /// for another tap against the new version.
    func save() async {
        guard canSave, let edited, let editBase, let held = session.snapshot else { return }
        isSaving = true
        message = nil
        notice = nil
        defer { isSaving = false }
        // Read again under this edit and changed elsewhere: never written over.
        guard DailyLimitValues(held) == editBase else {
            finish(.conflict)
            return
        }
        let service = session.family.service
        let childId = session.childId
        if hasTrustLadderChange {
            let minutes = edited.trustBonusMinutes
            let version = session.version ?? held.version
            let outcome = await session.write { try await service.setTrustLadder(minutes, of: childId, version: version) }
            guard outcome == .saved else {
                finish(outcome)
                return
            }
            self.editBase?.trustBonusMinutes = minutes
        }
        if hasLimitChange {
            let current = session.snapshot ?? held
            let limit = ScreenTimeLimit(
                schoolDayMinutes: edited.schoolDayMinutes,
                weekendMinutes: edited.weekendMinutes,
                maxDailyBonusMinutes: current.screenTime.maxDailyBonusMinutes
            )
            let version = current.version
            let outcome = await session.write { try await service.setScreenTime(limit, of: childId, version: version) }
            guard outcome == .saved else {
                finish(outcome)
                return
            }
        }
        finish(.saved)
    }

    private func finish(_ outcome: RuleSaveOutcome) {
        switch outcome {
        case .saved:
            discardEdit()
            notice = .saved
        case .conflict:
            discardEdit()
            notice = .conflict
        case .failed(let failure):
            message = failure
        case .cancelled:
            break
        }
    }

    private func edit(_ change: (inout DailyLimitValues) -> Void) {
        guard var copy = values else { return }
        if edited == nil {
            editBase = session.snapshot.map(DailyLimitValues.init)
        }
        change(&copy)
        edited = copy
        notice = nil
        message = nil
    }

    private func discardEdit() {
        edited = nil
        editBase = nil
        sameEveryDayChoice = nil
    }
}
