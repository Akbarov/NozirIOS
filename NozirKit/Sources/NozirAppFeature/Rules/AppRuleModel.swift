import Foundation
import Observation
import NozirFamily

/// One app's rule (Android `AppRuleEditor`, on a screen of its own: spec D1).
///
/// Only the edit lives here; the saved rule is the session's, found by
/// package. A save is checked against what the edit started from for this
/// package only: another app's rule, or P09/P10/P12 saved meanwhile, moves
/// the version this one writes against and is no conflict.
@MainActor
@Observable
final class AppRuleModel {
    static let defaultDailyLimitMinutes = 30
    /// A school morning (Android `AppRuleDraft.DEFAULT_WINDOW`).
    static let defaultWindow = BlockWindow(
        start: ClockTime(hour: 8, minute: 0),
        end: ClockTime(hour: 13, minute: 0),
        days: [1, 2, 3, 4, 5]
    )

    let session: ChildRulesSession
    let packageId: String
    /// The phone's name for the app when P11 knew one.
    let displayName: String?
    /// The edit; nil while nothing has been touched.
    private(set) var edited: AppPolicy?
    /// What the edit started from: this app's rule as the session held it,
    /// nil for an app that had none. Read only while `edited` is set.
    private(set) var editBase: AppPolicy?
    private(set) var isSaving = false
    private(set) var message: UserMessage?
    private(set) var notice: RuleNotice?

    init(session: ChildRulesSession, packageId: String, displayName: String?) {
        self.session = session
        self.packageId = packageId
        self.displayName = displayName
    }

    /// This app's rule as the session holds it; nil while it has none.
    var saved: AppPolicy? {
        session.snapshot?.appPolicies.first { $0.packageId == packageId }
    }

    /// What the editor shows: the edit, else the saved rule, else "no limit"
    /// for an app without one. nil until the rules have been read.
    var policy: AppPolicy? {
        guard session.snapshot != nil else { return nil }
        return edited ?? saved ?? AppPolicy(packageId: packageId, displayName: sentName, mode: .unrestricted)
    }

    /// Goes with every save: the server rewrites the name each time.
    var sentName: String? {
        displayName ?? saved?.displayName ?? editBase?.displayName
    }

    var name: String {
        AppRuleTexts.name(packageId: packageId, displayName: sentName)
    }

    /// Every app gets all four modes, "Doim yopiq" included (spec D2: the
    /// parent may close any app for good, no confirmation). Only a package
    /// the server never blocks is held to "Cheklov yo'q".
    var modes: [AppPolicyMode] {
        // The server answers 400 to a rule on a package it never blocks.
        if session.snapshot?.neverBlockedPackages.contains(packageId) == true { return [.unrestricted] }
        return [.unrestricted, .dailyLimit, .scheduleBlock, .alwaysBlocked]
    }

    /// nil for a mode this app has no segment for: none is lit.
    var selectedMode: AppPolicyMode? {
        guard let mode = policy?.mode, modes.contains(mode) else { return nil }
        return mode
    }

    /// The window the editor shows: a schedule's first. Any others go back as they came.
    var window: BlockWindow? {
        guard let policy, policy.mode == .scheduleBlock else { return nil }
        return policy.blockWindows.first ?? Self.defaultWindow
    }

    /// An app with no rule has one to save as it stands: "no limit" is a row.
    var hasChange: Bool {
        guard let edited else { return session.snapshot != nil && saved == nil }
        guard let editBase else { return true }
        return !Self.same(edited, editBase)
    }

    /// A mode this app does not know is never sent: the server would refuse it.
    var canSave: Bool {
        guard !isSaving, !session.isWriting, !session.isFrozen, session.version != nil, let policy else { return false }
        if case .unknown = policy.mode { return false }
        return hasChange
    }

    func load() async {
        await session.load()
    }

    /// The saved mode again is the saved rule again: tapping away and back is no change.
    func setMode(_ mode: AppPolicyMode) {
        guard modes.contains(mode) else { return }
        let base = edited == nil ? saved : editBase
        edit { policy in
            if let base, base.mode == mode {
                policy = base
            } else {
                policy = Self.withMode(policy, mode)
            }
        }
    }

    func setDailyLimitMinutes(_ minutes: Int) {
        guard policy?.mode == .dailyLimit else { return }
        edit { $0.dailyLimitMinutes = minutes }
    }

    func setWindowStart(_ time: ClockTime) {
        editWindow { $0.start = time }
    }

    func setWindowEnd(_ time: ClockTime) {
        editWindow { $0.end = time }
    }

    /// The last day stays on: the server refuses a window with none.
    func toggleDay(_ day: Int) {
        editWindow { $0.days = RuleDays.toggled(Set($0.days), day).sorted() }
    }

    /// What each mode needs to be a rule the server accepts (Android `AppRuleDraft.withMode`).
    static func withMode(_ policy: AppPolicy, _ mode: AppPolicyMode) -> AppPolicy {
        var changed = policy
        changed.mode = mode
        switch mode {
        case .unrestricted, .alwaysBlocked:
            changed.dailyLimitMinutes = nil
            changed.blockWindows = []
        case .dailyLimit:
            changed.dailyLimitMinutes = policy.dailyLimitMinutes ?? defaultDailyLimitMinutes
            changed.blockWindows = []
        case .scheduleBlock:
            changed.dailyLimitMinutes = nil
            changed.blockWindows = policy.blockWindows.isEmpty ? [defaultWindow] : policy.blockWindows
        case .unknown:
            break
        }
        return changed
    }

    func save() async {
        guard canSave, let policy, let held = session.snapshot else { return }
        isSaving = true
        message = nil
        notice = nil
        defer { isSaving = false }
        // Untouched, only an app with no rule gets here (`hasChange`): its base is none.
        let base = edited == nil ? nil : editBase
        // Changed on another phone under the edit (a refresh brought it): never written over.
        let current = held.appPolicies.first { $0.packageId == packageId }
        guard Self.same(current, base) else {
            discardEdit()
            notice = .conflict
            return
        }
        var named = policy
        named.displayName = sentName
        let body = named
        let service = session.family.service
        let childId = session.childId
        let version = held.version
        let outcome = await session.write { try await service.setAppPolicy(body, of: childId, version: version) }
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

    private func edit(_ change: (inout AppPolicy) -> Void) {
        guard var copy = policy else { return }
        if edited == nil {
            editBase = saved
        }
        change(&copy)
        edited = copy
        notice = nil
        message = nil
    }

    private func editWindow(_ change: (inout BlockWindow) -> Void) {
        guard let window else { return }
        edit { policy in
            var changed = window
            change(&changed)
            policy.blockWindows = [changed] + policy.blockWindows.dropFirst()
        }
    }

    /// The name is not part of the rule; the days are a set and the windows
    /// have no order (the server returns them without one).
    private static func same(_ lhs: AppPolicy?, _ rhs: AppPolicy?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        guard lhs.mode == rhs.mode,
              lhs.dailyLimitMinutes == rhs.dailyLimitMinutes,
              lhs.blockWindows.count == rhs.blockWindows.count else { return false }
        return zip(canonical(lhs.blockWindows), canonical(rhs.blockWindows)).allSatisfy { $0 == $1 }
    }

    private struct WindowKey: Comparable {
        let start: Int
        let end: Int
        let days: [Int]

        static func < (lhs: WindowKey, rhs: WindowKey) -> Bool {
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end < rhs.end }
            return lhs.days.lexicographicallyPrecedes(rhs.days)
        }
    }

    private static func canonical(_ windows: [BlockWindow]) -> [WindowKey] {
        windows.map {
            WindowKey(
                start: $0.start.hour * 60 + $0.start.minute,
                end: $0.end.hour * 60 + $0.end.minute,
                days: Set($0.days).sorted()
            )
        }.sorted()
    }

    private func discardEdit() {
        edited = nil
        editBase = nil
    }
}
