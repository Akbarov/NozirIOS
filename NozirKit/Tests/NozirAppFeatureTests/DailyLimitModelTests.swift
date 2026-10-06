import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let conflict = ApiFailure.server(status: 409, error: ApiError(code: .conflict))
private let sameDays = ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 120, maxDailyBonusMinutes: 60)

/// The model over a loaded session, as P09 shows it.
@MainActor
private func setup(_ script: FakeFamily.Script) async -> (DailyLimitModel, ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    let session = ChildRulesSession(childId: ali.id, family: family)
    let model = DailyLimitModel(session: session)
    await model.load()
    return (model, session, fake)
}

@MainActor
@Suite struct DailyLimitModelTests {
    @Test func theRuleIsShownAndNothingIsSavedUntilItChanges() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, trust: 30))]
        let (model, _, _) = await setup(script)

        #expect(model.values == DailyLimitValues(schoolDayMinutes: 120, weekendMinutes: 180, trustBonusMinutes: 30))
        #expect(!model.isSameEveryDay)
        #expect(!model.canSave)

        model.setWeekendMinutes(150)

        #expect(model.hasLimitChange)
        #expect(!model.hasTrustLadderChange)
        #expect(model.canSave)
    }

    @Test func sameEveryDayMovesBothDaysTogether() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, limit: sameDays))]
        let (model, _, _) = await setup(script)
        #expect(model.isSameEveryDay)

        model.setSchoolDayMinutes(90)
        #expect(model.values?.weekendMinutes == 90)

        model.setSameEveryDay(false)
        model.setSchoolDayMinutes(60)
        #expect(model.values?.schoolDayMinutes == 60)
        #expect(model.values?.weekendMinutes == 90)
    }

    @Test func turningSameEveryDayOnGivesTheWeekendTheSchoolDay() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (model, _, _) = await setup(script)

        model.setSameEveryDay(true)

        #expect(model.isSameEveryDay)
        #expect(model.values?.weekendMinutes == 120)
        #expect(model.hasLimitChange)
    }

    @Test func aLimitOnlySaveCarriesTheBonusCeilingAndSkipsTheLadder() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let saved = ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 60)
        script.screenTime = [.success(snapshot(version: 5, limit: saved))]
        let (model, session, fake) = await setup(script)
        model.setSchoolDayMinutes(90)

        await model.save()

        #expect(await fake.screenTimeWrites == [RuleWrite(value: saved, version: 4)])
        #expect(await fake.trustLadderWrites.isEmpty)
        #expect(model.notice == .saved)
        #expect(session.version == 5)
        #expect(model.edited == nil)
        #expect(!model.canSave)
    }

    @Test func aLadderOnlySaveSkipsTheLimit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.trustLadder = [.success(snapshot(version: 5, trust: 45))]
        let (model, session, fake) = await setup(script)
        model.setTrustBonusMinutes(45)

        await model.save()

        #expect(await fake.trustLadderWrites == [RuleWrite(value: 45, version: 4)])
        #expect(await fake.screenTimeWrites.isEmpty)
        #expect(model.notice == .saved)
        #expect(session.snapshot?.maxTrustBonusMinutes == 45)
    }

    @Test func bothChangesGoLadderFirstThenTheLimitOnTheNewVersion() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.trustLadder = [.success(snapshot(version: 5, trust: 30))]
        let limit = ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 60)
        script.screenTime = [.success(snapshot(version: 6, limit: limit, trust: 30))]
        let (model, session, fake) = await setup(script)
        model.setTrustBonusMinutes(30)
        model.setSchoolDayMinutes(90)

        await model.save()

        #expect(await fake.calls.filter { $0 == "trustLadder" || $0 == "screenTime" } == ["trustLadder", "screenTime"])
        #expect(await fake.trustLadderWrites.map(\.version) == [4])
        #expect(await fake.screenTimeWrites.map(\.version) == [5])
        #expect(session.version == 6)
        #expect(model.notice == .saved)
    }

    // Review Focus 1.
    @Test func aLimitFailureAfterTheLadderKeepsTheLadderAndRetriesOnTheNewVersion() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.trustLadder = [.success(snapshot(version: 5, trust: 30))]
        let limit = ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 60)
        script.screenTime = [.failure(offline), .success(snapshot(version: 6, limit: limit, trust: 30))]
        let (model, session, fake) = await setup(script)
        model.setTrustBonusMinutes(30)
        model.setSchoolDayMinutes(90)

        await model.save()

        #expect(model.message == .noConnection)
        #expect(model.notice == nil)
        #expect(session.version == 5)
        #expect(session.snapshot?.maxTrustBonusMinutes == 30)
        #expect(model.values == DailyLimitValues(schoolDayMinutes: 90, weekendMinutes: 180, trustBonusMinutes: 30))
        #expect(!model.hasTrustLadderChange)
        #expect(model.hasLimitChange)
        #expect(model.canSave)

        await model.save()

        #expect(await fake.trustLadderWrites.count == 1)
        #expect(await fake.screenTimeWrites.map(\.version) == [5, 5])
        #expect(model.notice == .saved)
        #expect(model.message == nil)
        #expect(session.version == 6)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func aRefusedLadderStopsBeforeTheLimit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.trustLadder = [.failure(.server(status: 403, error: ApiError(code: .childNotActive)))]
        let (model, session, fake) = await setup(script)
        model.setTrustBonusMinutes(30)
        model.setSchoolDayMinutes(90)

        await model.save()

        #expect(await fake.screenTimeWrites.isEmpty)
        #expect(model.message == .childNotActive)
        #expect(session.version == 4)
        #expect(model.canSave)
    }

    @Test func aConflictShowsTheLatestAndDoesNotResend() async {
        var script = FakeFamily.Script()
        let elsewhere = ScreenTimeLimit(schoolDayMinutes: 150, weekendMinutes: 150, maxDailyBonusMinutes: 60)
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 7, limit: elsewhere))]
        script.screenTime = [.failure(conflict)]
        let (model, session, fake) = await setup(script)
        model.setSchoolDayMinutes(90)

        await model.save()

        #expect(model.notice == .conflict)
        #expect(session.version == 7)
        #expect(model.values == DailyLimitValues(schoolDayMinutes: 150, weekendMinutes: 150, trustBonusMinutes: 0))
        #expect(model.isSameEveryDay)
        #expect(!model.canSave)
        #expect(await fake.screenTimeWrites.count == 1)
    }

    @Test func aRuleChangedElsewhereUnderTheEditIsNotWrittenOver() async {
        var script = FakeFamily.Script()
        let elsewhere = ScreenTimeLimit(schoolDayMinutes: 60, weekendMinutes: 60, maxDailyBonusMinutes: 60)
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 5, limit: elsewhere))]
        let (model, session, fake) = await setup(script)
        model.setSchoolDayMinutes(90)
        await session.reload()

        await model.save()

        #expect(await fake.screenTimeWrites.isEmpty)
        #expect(model.notice == .conflict)
        #expect(model.values?.schoolDayMinutes == 60)
    }

    // Review Focus 4.
    @Test func loadingAgainKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 4))]
        let (model, _, fake) = await setup(script)
        model.setSchoolDayMinutes(90)
        model.setTrustBonusMinutes(15)

        await model.load()

        #expect(model.values == DailyLimitValues(schoolDayMinutes: 90, weekendMinutes: 180, trustBonusMinutes: 15))
        #expect(model.canSave)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func aSaveOnAnotherScreenLeavesTheEditInPlace() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (model, session, _) = await setup(script)
        model.setSchoolDayMinutes(90)

        session.accept(snapshot(version: 5, bedtime: BedtimeSchedule(start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 7, minute: 0), windDownMinutes: 30, activeDays: [1, 2, 3, 4, 5, 6, 7])))

        #expect(model.values?.schoolDayMinutes == 90)
        #expect(model.canSave)
    }

    @Test func theLimitSaveCarriesACeilingP12JustSaved() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.screenTime = [.success(snapshot(version: 6))]
        let (model, session, fake) = await setup(script)
        model.setSchoolDayMinutes(90)
        session.acceptBonus(version: 5, ceiling: 30)

        await model.save()

        #expect(await fake.screenTimeWrites == [RuleWrite(value: ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 30), version: 5)])
    }

    // Review Focus 5.
    @Test(.timeLimit(.minutes(5)))
    func twoTapsSaveOnce() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.screenTime = [.success(snapshot(version: 5))]
        script.writeGate = gate
        let (model, _, fake) = await setup(script)
        model.setSchoolDayMinutes(90)

        let first = Task { await model.save() }
        await gate.untilPaused()
        #expect(model.isSaving)
        #expect(!model.canSave)
        await model.save()
        #expect(await fake.screenTimeWrites.count == 1)

        await gate.release()
        await first.value
        #expect(model.notice == .saved)
        #expect(await fake.screenTimeWrites.count == 1)
    }

    @Test func aFrozenChildCannotSave() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        let (model, session, fake) = await setup(script)
        #expect(session.isFrozen)
        model.setSchoolDayMinutes(90)

        #expect(!model.canSave)
        await model.save()

        #expect(await fake.screenTimeWrites.isEmpty)
        #expect(await fake.trustLadderWrites.isEmpty)
    }

    @Test func aCancelledSaveSaysNothingAndKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.cancelNextWrite = true
        let (model, _, _) = await setup(script)
        model.setSchoolDayMinutes(90)

        await model.save()

        #expect(model.notice == nil)
        #expect(model.message == nil)
        #expect(model.edited?.schoolDayMinutes == 90)
        #expect(!model.isSaving)
        #expect(model.canSave)
    }
}
