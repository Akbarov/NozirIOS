import Foundation
import Observation
import NozirFamily
import NozirL10n

/// P03b (Android `NewChildRulesViewModel`): the first limit and bedtime, saved
/// together with the child.
@MainActor
@Observable
public final class NewChildRulesModel {
    static let windDownWhenOn = 30

    public let draft: ChildDraft
    public var schoolDayMinutes = 120
    public var weekendMinutes = 180
    public private(set) var maxDailyBonusMinutes = 60
    public var bedtimeStart = ClockTime(hour: 22, minute: 0)
    public var bedtimeEnd = ClockTime(hour: 7, minute: 0)
    public private(set) var windDownMinutes = NewChildRulesModel.windDownWhenOn
    public private(set) var activeDays: Set<Int> = Set(1...7)
    public private(set) var isPrefilledFromSibling = false
    public private(set) var isSaving = false
    public private(set) var message: UserMessage?
    /// Kept across attempts: a second "Save" must not add a second child.
    @ObservationIgnored private var created: Child?
    private let family: FamilyStore

    public init(draft: ChildDraft, family: FamilyStore) {
        self.draft = draft
        self.family = family
    }

    /// Starts from the rules of the child added last, as Android does. Quiet
    /// when there is none or they cannot be read: the defaults stand.
    public func prefill() async {
        guard !isPrefilledFromSibling, created == nil, let sibling = family.children.last else { return }
        guard let rules = try? await family.service.rules(of: sibling.id) else { return }
        schoolDayMinutes = rules.screenTime.schoolDayMinutes
        weekendMinutes = rules.screenTime.weekendMinutes
        maxDailyBonusMinutes = rules.screenTime.maxDailyBonusMinutes
        bedtimeStart = rules.bedtime.start
        bedtimeEnd = rules.bedtime.end
        windDownMinutes = rules.bedtime.windDownMinutes
        activeDays = Set(rules.bedtime.activeDays)
        isPrefilledFromSibling = true
    }

    public var isWindDownOn: Bool {
        windDownMinutes > 0
    }

    public func setWindDown(on: Bool) {
        windDownMinutes = on ? Self.windDownWhenOn : 0
    }

    public func setWindDownMinutes(_ minutes: Int) {
        guard isWindDownOn else { return }
        windDownMinutes = minutes
    }

    /// At least one night stays on.
    public func toggleDay(_ day: Int) {
        if activeDays.contains(day) {
            guard activeDays.count > 1 else { return }
            activeDays.remove(day)
        } else if (1...7).contains(day) {
            activeDays.insert(day)
        }
    }

    public var limit: ScreenTimeLimit {
        ScreenTimeLimit(schoolDayMinutes: schoolDayMinutes, weekendMinutes: weekendMinutes, maxDailyBonusMinutes: maxDailyBonusMinutes)
    }

    public var bedtime: BedtimeSchedule {
        BedtimeSchedule(start: bedtimeStart, end: bedtimeEnd, windDownMinutes: windDownMinutes, activeDays: activeDays.sorted())
    }

    /// Creates the child once, then writes each rule set against the version
    /// the answer before it gave. Any failure is shown and the child is kept;
    /// a 409 is never resent on its own (openapi `RuleVersionConflict`).
    public func save() async -> Child? {
        guard !isSaving else { return nil }
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            let child: Child
            if let created {
                child = created
            } else {
                child = try await family.service.createChild(draft.create)
                created = child
                family.replace(child)
            }
            let current = try await family.service.rules(of: child.id)
            let afterLimit = try await family.service.setScreenTime(limit, of: child.id, version: current.version)
            _ = try await family.service.setBedtime(bedtime, of: child.id, version: afterLimit.version)
            return child
        } catch {
            message = UserMessage(error)
            return nil
        }
    }

    /// "Har kuni", or "Faol tunlar: Dushanba, Chorshanba".
    static func daysSummary(_ days: Set<Int>, _ l10n: L10n) -> String {
        if days.count == 7 { return l10n.bedtimeDaysEveryNight }
        let names = days.sorted().compactMap { day in
            l10n.weekdayNames.indices.contains(day - 1) ? l10n.weekdayNames[day - 1] : nil
        }
        return l10n.bedtimeDaysSummary(names.joined(separator: l10n.bedtimeDaysSeparator))
    }
}
