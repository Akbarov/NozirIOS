import Foundation
import Testing
import NozirFamily
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

private let draft = ChildDraft(displayName: "Ali", birthYear: 2015, avatarKey: "teal", phoneE164: nil)

@MainActor
private func setup(_ script: FakeFamily.Script = .init(), siblings: [Child] = []) -> (NewChildRulesModel, FakeFamily, FamilyStore) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    siblings.forEach(family.replace)
    return (NewChildRulesModel(draft: draft, family: family), fake, family)
}

@MainActor
@Suite struct NewChildRulesModelTests {
    @Test func aFirstChildStartsFromTheDefaults() async {
        let (model, fake, _) = setup()

        await model.prefill()

        #expect(model.limit == ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 180, maxDailyBonusMinutes: 60))
        #expect(model.bedtime == defaultBedtime)
        #expect(!model.isPrefilledFromSibling)
        #expect(await fake.calls.isEmpty)
    }

    @Test func aSecondChildStartsFromTheLastChildsRules() async {
        var script = FakeFamily.Script()
        let siblingBedtime = BedtimeSchedule(start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 6, minute: 30), windDownMinutes: 0, activeDays: [1, 2, 3, 4, 5])
        script.rules = [.success(snapshot(version: 3, limit: ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 150, maxDailyBonusMinutes: 45), bedtime: siblingBedtime))]
        let (model, _, _) = setup(script, siblings: [makeChild("Vali"), makeChild("Sardor")])

        await model.prefill()

        #expect(model.limit == ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 150, maxDailyBonusMinutes: 45))
        #expect(model.bedtime == siblingBedtime)
        #expect(model.isPrefilledFromSibling)
    }

    @Test func aSiblingWhoseRulesCannotBeReadLeavesTheDefaultsQuietly() async {
        let (model, _, _) = setup(siblings: [makeChild("Vali")])

        await model.prefill()

        #expect(model.limit == defaultLimit)
        #expect(!model.isPrefilledFromSibling)
        #expect(model.message == nil)
    }

    // Review Focus 5.
    @Test func siblingValuesOutsideTheSliderAreKeptAsTheyAre() async {
        var script = FakeFamily.Script()
        script.rules = [
            .success(snapshot(version: 3, limit: ScreenTimeLimit(schoolDayMinutes: 0, weekendMinutes: 480, maxDailyBonusMinutes: 60))),
            .success(snapshot(version: 1)),
        ]
        script.create = [.success(makeChild("Ali"))]
        script.screenTime = [.success(snapshot(version: 2))]
        script.bedtime = [.success(snapshot(version: 3))]
        let (model, fake, _) = setup(script, siblings: [makeChild("Vali")])

        await model.prefill()
        _ = await model.save()

        #expect(model.schoolDayMinutes == 0)
        #expect(await fake.screenTimeWrites.first?.value == ScreenTimeLimit(schoolDayMinutes: 0, weekendMinutes: 480, maxDailyBonusMinutes: 60))
    }

    @Test func theLastNightCannotBeTurnedOff() {
        let (model, _, _) = setup()
        for day in 1...6 { model.toggleDay(day) }
        #expect(model.activeDays == [7])

        model.toggleDay(7)

        #expect(model.activeDays == [7])
    }

    @Test func windDownOffIsZeroAndOnIsThirty() {
        let (model, _, _) = setup()

        model.setWindDown(on: false)
        #expect(model.bedtime.windDownMinutes == 0)
        model.setWindDownMinutes(45)
        #expect(model.windDownMinutes == 0)

        model.setWindDown(on: true)
        #expect(model.windDownMinutes == 30)
    }

    @Test func savingCreatesTheChildThenWritesEachRuleAgainstTheVersionBeforeIt() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.create = [.success(ali)]
        script.rules = [.success(snapshot(version: 5))]
        script.screenTime = [.success(snapshot(version: 6))]
        script.bedtime = [.success(snapshot(version: 7))]
        let (model, fake, family) = setup(script)
        model.schoolDayMinutes = 90

        let saved = await model.save()

        #expect(saved == ali)
        #expect(await fake.created == [draft.create])
        #expect(await fake.screenTimeWrites == [RuleWrite(value: ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 60), version: 5)])
        #expect(await fake.bedtimeWrites.map(\.version) == [6])
        #expect(family.child(ali.id) == ali)
        #expect(!model.isSaving)
    }

    @Test func theChildLimitStopsBeforeAnyRule() async {
        var script = FakeFamily.Script()
        script.create = [.failure(.server(status: 403, error: ApiError(code: .childLimitReached)))]
        let (model, fake, _) = setup(script)

        let saved = await model.save()

        #expect(saved == nil)
        #expect(model.message == .childLimitReached)
        #expect(await fake.calls == ["create"])
    }

    @Test func aConflictIsShownAndNotResentBlindly() async {
        var script = FakeFamily.Script()
        script.create = [.success(makeChild("Ali"))]
        script.rules = [.success(snapshot(version: 5))]
        script.screenTime = [.failure(.server(status: 409, error: ApiError(code: .conflict)))]
        let (model, fake, _) = setup(script)

        let saved = await model.save()

        #expect(saved == nil)
        #expect(model.message == .conflict)
        #expect(await fake.calls == ["create", "rules", "screenTime"])
    }

    @Test func theChildCountsAsCreatedOnceItIsSavedEvenIfTheRulesFail() async {
        var script = FakeFamily.Script()
        script.create = [.success(makeChild("Ali"))]
        script.rules = [.failure(offline)]
        let (model, _, _) = setup(script)
        #expect(!model.hasCreatedChild)

        #expect(await model.save() == nil)

        #expect(model.hasCreatedChild)
    }

    // Review Focus 2.
    @Test func savingAgainAfterAFailureDoesNotCreateASecondChild() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.create = [.success(ali)]
        script.rules = [.failure(offline), .success(snapshot(version: 8))]
        script.screenTime = [.success(snapshot(version: 9))]
        script.bedtime = [.success(snapshot(version: 10))]
        let (model, fake, _) = setup(script)

        #expect(await model.save() == nil)
        #expect(model.message == .noConnection)
        let saved = await model.save()

        #expect(saved == ali)
        #expect(model.message == nil)
        #expect(await fake.created.count == 1)
        #expect(await fake.screenTimeWrites.map(\.version) == [8])
    }

    @Test func theNightsAreNamed() {
        let l10n = L10n(.uz)
        #expect(NewChildRulesModel.daysSummary([1, 2, 3, 4, 5, 6, 7], l10n) == l10n.bedtimeDaysEveryNight)
        #expect(NewChildRulesModel.daysSummary([3, 1], l10n) == l10n.bedtimeDaysSummary("Dushanba, Chorshanba"))
    }
}

@Suite struct DurationsTests {
    @Test func shortAndLongReadAsAndroidWritesThem() {
        let l10n = L10n(.uz)
        #expect(Durations.short(150, l10n) == "2s 30d")
        #expect(Durations.short(45, l10n) == l10n.durationShortMinutes(45))
        #expect(Durations.long(540, l10n) == l10n.durationLongHoursMinutes(9, 0))
    }

    @Test func aSliderStretchesToHoldAValueOutsideIt() {
        #expect(Durations.range(30...360, including: 120) == 30...360)
        #expect(Durations.range(30...360, including: 0) == 0...360)
        #expect(Durations.range(30...360, including: 480) == 30...480)
    }

    @Test func aClockTimeSurvivesTheDatePicker() {
        let time = ClockTime(hour: 21, minute: 45)
        #expect(ClockTime(date: time.date()) == time)
    }
}
