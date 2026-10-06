import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let conflict = ApiFailure.server(status: 409, error: ApiError(code: .conflict))

private func night(start: ClockTime = ClockTime(hour: 22, minute: 0), windDown: Int = 30, days: [Int] = [1, 2, 3, 4, 5, 6, 7]) -> BedtimeSchedule {
    BedtimeSchedule(start: start, end: ClockTime(hour: 7, minute: 0), windDownMinutes: windDown, activeDays: days)
}

@MainActor
private func setup(_ script: FakeFamily.Script) async -> (BedtimeModel, ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    let session = ChildRulesSession(childId: ali.id, family: family)
    let model = BedtimeModel(session: session)
    await model.load()
    return (model, session, fake)
}

@MainActor
@Suite struct BedtimeModelTests {
    @Test func theWindowIsShownAndNothingIsSavedUntilItChanges() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (model, _, _) = await setup(script)

        #expect(model.bedtime == defaultBedtime)
        #expect(!model.canSave)

        model.setStart(ClockTime(hour: 21, minute: 30))

        #expect(model.bedtime?.start == ClockTime(hour: 21, minute: 30))
        #expect(model.canSave)
    }

    @Test func theLastNightCannotBeTurnedOff() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, bedtime: night(days: [3])))]
        let (model, _, _) = await setup(script)

        model.toggleDay(3)
        #expect(model.bedtime?.activeDays == [3])
        #expect(!model.canSave)

        model.toggleDay(1)
        #expect(model.bedtime?.activeDays == [1, 3])
    }

    @Test func aNightToggledOffAndOnAgainIsNoChange() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, bedtime: night(days: [5, 1, 3])))]
        let (model, _, _) = await setup(script)

        model.toggleDay(1)
        #expect(model.canSave)
        model.toggleDay(1)

        #expect(!model.hasChange)
        #expect(!model.canSave)
    }

    @Test func windDownComesBackAtItsOwnLength() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, bedtime: night(windDown: 45)))]
        let (model, _, _) = await setup(script)

        model.setWindDown(on: false)
        #expect(model.bedtime?.windDownMinutes == 0)
        #expect(!model.isWindDownOn)

        model.setWindDown(on: true)
        #expect(model.bedtime?.windDownMinutes == 45)
    }

    @Test func windDownFirstTurnedOnIsThirty() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, bedtime: night(windDown: 0)))]
        let (model, _, _) = await setup(script)

        model.setWindDownMinutes(60)
        #expect(model.bedtime?.windDownMinutes == 0)

        model.setWindDown(on: true)
        #expect(model.bedtime?.windDownMinutes == BedtimeModel.defaultWindDownMinutes)

        model.setWindDownMinutes(15)
        model.setWindDown(on: false)
        model.setWindDown(on: true)
        #expect(model.bedtime?.windDownMinutes == 15)
    }

    @Test func savingNamesTheSessionVersionAndHandsTheAnswerBack() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let changed = night(start: ClockTime(hour: 21, minute: 0), days: [1, 2, 3, 4, 5])
        script.bedtime = [.success(snapshot(version: 5, bedtime: changed))]
        let (model, session, fake) = await setup(script)
        model.setStart(ClockTime(hour: 21, minute: 0))
        model.toggleDay(6)
        model.toggleDay(7)

        await model.save()

        #expect(await fake.bedtimeWrites == [RuleWrite(value: changed, version: 4)])
        #expect(session.version == 5)
        #expect(model.notice == .saved)
        #expect(model.bedtime == changed)
        #expect(!model.canSave)
    }

    @Test func aConflictShowsTheLatestAndDoesNotResend() async {
        var script = FakeFamily.Script()
        let elsewhere = night(start: ClockTime(hour: 20, minute: 30))
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 8, bedtime: elsewhere))]
        script.bedtime = [.failure(conflict)]
        let (model, session, fake) = await setup(script)
        model.setStart(ClockTime(hour: 21, minute: 0))

        await model.save()

        #expect(model.notice == .conflict)
        #expect(session.version == 8)
        #expect(model.bedtime == elsewhere)
        #expect(!model.canSave)
        #expect(await fake.bedtimeWrites.count == 1)
    }

    @Test func aFailedSaveKeepsTheEditForAnotherTry() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bedtime = [.failure(.server(status: 500, error: ApiError(code: .internalError)))]
        let (model, _, _) = await setup(script)
        model.setStart(ClockTime(hour: 21, minute: 0))

        await model.save()

        #expect(model.message == .serverProblem)
        #expect(model.bedtime?.start == ClockTime(hour: 21, minute: 0))
        #expect(model.canSave)
    }

    // Review Focus 4.
    @Test func loadingAgainKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 4))]
        let (model, _, fake) = await setup(script)
        model.setStart(ClockTime(hour: 21, minute: 0))

        await model.load()

        #expect(model.bedtime?.start == ClockTime(hour: 21, minute: 0))
        #expect(model.canSave)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    // Review Focus 2.
    @Test func aBedtimeSaveDoesNotMakeTheOpenLimitEditConflict() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let later = night(start: ClockTime(hour: 21, minute: 30))
        script.bedtime = [.success(snapshot(version: 5, bedtime: later))]
        let limit = ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 60)
        script.screenTime = [.success(snapshot(version: 6, limit: limit, bedtime: later))]
        let (bedtime, session, fake) = await setup(script)
        let dailyLimit = DailyLimitModel(session: session)
        dailyLimit.setSchoolDayMinutes(90)

        bedtime.setStart(ClockTime(hour: 21, minute: 30))
        await bedtime.save()
        await dailyLimit.save()

        #expect(bedtime.notice == .saved)
        #expect(dailyLimit.notice == .saved)
        #expect(await fake.bedtimeWrites.map(\.version) == [4])
        #expect(await fake.screenTimeWrites == [RuleWrite(value: limit, version: 5)])
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
        #expect(session.version == 6)
    }

    @Test func aCancelledSaveSaysNothingAndKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.cancelNextWrite = true
        let (model, session, fake) = await setup(script)
        model.setStart(ClockTime(hour: 21, minute: 0))

        await model.save()

        #expect(model.notice == nil)
        #expect(model.message == nil)
        #expect(model.bedtime?.start == ClockTime(hour: 21, minute: 0))
        #expect(model.canSave)
        #expect(session.version == 4)
        #expect(await fake.bedtimeWrites.count == 1)
    }

    @Test func aFrozenChildCannotSave() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        let (model, _, fake) = await setup(script)
        model.setStart(ClockTime(hour: 21, minute: 0))

        await model.save()

        #expect(!model.canSave)
        #expect(await fake.bedtimeWrites.isEmpty)
    }
}
