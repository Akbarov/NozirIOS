import Foundation
import Observation
import NozirFamily

/// P10 (Android `BedtimeViewModel`): the night window, its nights, and the
/// warning before it. Only the edit lives here; the saved rule is the session's.
@MainActor
@Observable
final class BedtimeModel {
    /// The warning's length the first time it is switched on.
    static let defaultWindDownMinutes = 30

    let session: ChildRulesSession
    private(set) var edited: BedtimeSchedule?
    /// What the edit started from. A save checks it is still what the session holds.
    private(set) var editBase: BedtimeSchedule?
    private(set) var isSaving = false
    private(set) var message: UserMessage?
    private(set) var notice: RuleNotice?
    /// The warning's length before it was switched off: on again gives the
    /// parent's own number back rather than a default they never chose.
    @ObservationIgnored private var lastWindDownMinutes: Int?

    init(session: ChildRulesSession) {
        self.session = session
    }

    var bedtime: BedtimeSchedule? {
        edited ?? session.snapshot?.bedtime
    }

    var isWindDownOn: Bool {
        (bedtime?.windDownMinutes ?? 0) > 0
    }

    var hasChange: Bool {
        guard let edited, let editBase else { return false }
        return edited != editBase
    }

    var canSave: Bool {
        !isSaving && !session.isFrozen && session.version != nil && hasChange
    }

    func load() async {
        await session.load()
    }

    func setStart(_ time: ClockTime) {
        edit { $0.start = time }
    }

    func setEnd(_ time: ClockTime) {
        edit { $0.end = time }
    }

    /// The last night stays on.
    func toggleDay(_ day: Int) {
        edit { $0.activeDays = RuleDays.toggled(Set($0.activeDays), day).sorted() }
    }

    /// Off is 0, the only shape the child's phone understands.
    func setWindDown(on: Bool) {
        if on {
            let minutes = lastWindDownMinutes ?? Self.defaultWindDownMinutes
            edit { $0.windDownMinutes = minutes }
        } else {
            if let current = bedtime?.windDownMinutes, current > 0 {
                lastWindDownMinutes = current
            }
            edit { $0.windDownMinutes = 0 }
        }
    }

    func setWindDownMinutes(_ minutes: Int) {
        guard isWindDownOn else { return }
        lastWindDownMinutes = minutes
        edit { $0.windDownMinutes = minutes }
    }

    func save() async {
        guard canSave, let edited, let editBase, let held = session.snapshot else { return }
        isSaving = true
        message = nil
        notice = nil
        defer { isSaving = false }
        // Read again under this edit and changed elsewhere: never written over.
        guard held.bedtime == editBase else {
            discardEdit()
            notice = .conflict
            return
        }
        let service = session.family.service
        let childId = session.childId
        let version = held.version
        let outcome = await session.write { try await service.setBedtime(edited, of: childId, version: version) }
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

    private func edit(_ change: (inout BedtimeSchedule) -> Void) {
        guard var copy = bedtime else { return }
        if edited == nil {
            editBase = session.snapshot?.bedtime
        }
        change(&copy)
        edited = copy
        notice = nil
        message = nil
    }

    private func discardEdit() {
        edited = nil
        editBase = nil
    }
}
