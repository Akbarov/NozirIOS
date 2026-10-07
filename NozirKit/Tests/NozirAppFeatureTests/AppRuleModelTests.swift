import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let conflict = ApiFailure.server(status: 409, error: ApiError(code: .conflict))
private let roblox = "com.roblox.client"
private let mine = appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 30)
private let anHour = appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 60)

@MainActor
private func makeModel(
    _ script: FakeFamily.Script,
    packageId: String = roblox,
    displayName: String? = "Roblox"
) -> (AppRuleModel, ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    let session = ChildRulesSession(childId: ali.id, family: family)
    return (AppRuleModel(session: session, packageId: packageId, displayName: displayName), session, fake)
}

/// The editor over a loaded session, as P11 opens it.
@MainActor
private func setup(
    _ script: FakeFamily.Script,
    packageId: String = roblox,
    displayName: String? = "Roblox"
) async -> (AppRuleModel, ChildRulesSession, FakeFamily) {
    let (model, session, fake) = makeModel(script, packageId: packageId, displayName: displayName)
    await model.load()
    return (model, session, fake)
}

@MainActor
@Suite struct AppRuleModelTests {
    @Test func aNewAppStartsWithNoLimitAndThatCanBeSaved() async {
        let saved = appPolicy(roblox, name: "Roblox", mode: .unrestricted)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [saved]))]
        let (model, session, fake) = await setup(script)

        #expect(model.policy == saved)
        #expect(model.name == "Roblox")
        #expect(model.selectedMode == .unrestricted)
        #expect(model.modes == [.unrestricted, .dailyLimit, .scheduleBlock, .alwaysBlocked])
        #expect(model.canSave)

        await model.save()

        #expect(await fake.appPolicyWrites == [RuleWrite(value: saved, version: 4)])
        #expect(session.version == 5)
        #expect(model.notice == .saved)
        #expect(model.policy == saved)
        #expect(!model.canSave)
    }

    @Test func anUnchangedRuleHasNothingToSave() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 45)]))]
        let (model, _, _) = await setup(script)

        #expect(model.selectedMode == .dailyLimit)
        #expect(!model.canSave)

        model.setDailyLimitMinutes(60)
        #expect(model.canSave)

        model.setDailyLimitMinutes(45)
        #expect(!model.hasChange)
        #expect(!model.canSave)
    }

    @Test func dailyTimeStartsAtThirtyAndAScheduleAtSchoolHours() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (model, _, _) = await setup(script)

        model.setMode(.dailyLimit)
        #expect(model.policy?.dailyLimitMinutes == AppRuleModel.defaultDailyLimitMinutes)
        #expect(model.policy?.blockWindows == [])
        #expect(model.window == nil)

        model.setMode(.scheduleBlock)
        #expect(model.policy?.dailyLimitMinutes == nil)
        #expect(model.policy?.blockWindows == [schoolHours])
        #expect(model.window == AppRuleModel.defaultWindow)

        model.setMode(.unrestricted)
        #expect(model.policy?.dailyLimitMinutes == nil)
        #expect(model.policy?.blockWindows == [])
        #expect(model.canSave)
    }

    @Test func goingBackToTheSavedModeIsNoChange() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 45)]))]
        let (model, _, _) = await setup(script)

        model.setMode(.scheduleBlock)
        #expect(model.window == AppRuleModel.defaultWindow)
        #expect(model.canSave)

        model.setMode(.dailyLimit)
        #expect(model.policy?.dailyLimitMinutes == 45)
        #expect(!model.canSave)
    }

    @Test func minutesAndHoursAreOnlyEditedInTheirOwnMode() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        let (model, _, _) = await setup(script)

        model.setWindowStart(ClockTime(hour: 9, minute: 0))
        model.toggleDay(6)
        #expect(model.edited == nil)

        // A mode this app has no segment for is ignored.
        model.setMode(.unknown("FOCUS_ONLY"))
        #expect(model.policy == mine)
        #expect(!model.canSave)
    }

    // Review Focus 1.
    @Test func anAlwaysClosedRuleOpenedAndSavedUntouchedStaysAlwaysClosed() async {
        let always = appPolicy(roblox, name: "Roblox", mode: .alwaysBlocked)
        let daily = appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 30)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [always]))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [daily]))]
        let (model, _, fake) = await setup(script)

        #expect(model.modes == [.unrestricted, .dailyLimit, .scheduleBlock, .alwaysBlocked])
        #expect(model.selectedMode == .alwaysBlocked)
        #expect(!model.canSave)
        await model.save()
        #expect(await fake.appPolicyWrites.isEmpty)

        model.setMode(.dailyLimit)
        model.setMode(.alwaysBlocked)
        #expect(model.policy == always)
        #expect(!model.canSave)

        model.setMode(.dailyLimit)
        await model.save()

        #expect(await fake.appPolicyWrites == [RuleWrite(value: daily, version: 4)])
        #expect(model.modes == [.unrestricted, .dailyLimit, .scheduleBlock, .alwaysBlocked])
        #expect(model.selectedMode == .dailyLimit)
    }

    @Test func anUnknownModeIsKeptUntilAnotherIsChosen() async {
        let future = appPolicy(roblox, name: "Roblox", mode: .unknown("FOCUS_ONLY"), minutes: 20)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [future]))]
        let (model, _, fake) = await setup(script)

        #expect(model.selectedMode == nil)
        #expect(model.modes == [.unrestricted, .dailyLimit, .scheduleBlock, .alwaysBlocked])
        #expect(!model.canSave)

        model.setDailyLimitMinutes(60)
        #expect(model.policy == future)
        await model.save()
        #expect(await fake.appPolicyWrites.isEmpty)

        model.setMode(.unrestricted)
        #expect(model.selectedMode == .unrestricted)
        #expect(model.policy?.dailyLimitMinutes == nil)
        #expect(model.canSave)
    }

    @Test func theLastDayOfAWindowStaysOn() async {
        let oneDay = BlockWindow(start: ClockTime(hour: 8, minute: 0), end: ClockTime(hour: 13, minute: 0), days: [3])
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [appPolicy(roblox, mode: .scheduleBlock, windows: [oneDay])]))]
        let (model, _, _) = await setup(script)

        model.toggleDay(3)
        #expect(model.window?.days == [3])
        #expect(!model.canSave)

        model.toggleDay(1)
        #expect(model.window?.days == [1, 3])
        #expect(model.canSave)
    }

    @Test func aDayToggledOffAndOnAgainIsNoChange() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [appPolicy(roblox, mode: .scheduleBlock, windows: [schoolHours])]))]
        let (model, _, _) = await setup(script)

        model.toggleDay(2)
        #expect(model.canSave)
        model.toggleDay(2)

        #expect(model.window?.days == [1, 2, 3, 4, 5])
        #expect(!model.canSave)
    }

    // Review Focus 4.
    @Test func editingTheFirstWindowKeepsTheSecond() async {
        let evening = BlockWindow(start: ClockTime(hour: 19, minute: 0), end: ClockTime(hour: 21, minute: 0), days: [6, 7])
        let later = BlockWindow(start: ClockTime(hour: 9, minute: 0), end: schoolHours.end, days: schoolHours.days)
        let sent = appPolicy(roblox, name: "Roblox", mode: .scheduleBlock, windows: [later, evening])
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [appPolicy(roblox, name: "Roblox", mode: .scheduleBlock, windows: [schoolHours, evening])]))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [sent]))]
        let (model, _, fake) = await setup(script)

        model.setWindowStart(ClockTime(hour: 9, minute: 0))
        #expect(model.window == later)
        await model.save()

        #expect(await fake.appPolicyWrites == [RuleWrite(value: sent, version: 4)])
        #expect(model.policy?.blockWindows == [later, evening])
    }

    @Test func aScheduleIsSentWithItsHoursDaysAndName() async {
        let sent = appPolicy(
            roblox,
            name: "Roblox",
            mode: .scheduleBlock,
            windows: [BlockWindow(start: ClockTime(hour: 8, minute: 0), end: ClockTime(hour: 14, minute: 30), days: [1, 2, 3, 4])]
        )
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [sent]))]
        let (model, session, fake) = await setup(script)

        model.setMode(.scheduleBlock)
        model.setWindowEnd(ClockTime(hour: 14, minute: 30))
        model.toggleDay(5)
        await model.save()

        #expect(await fake.appPolicyWrites == [RuleWrite(value: sent, version: 4)])
        #expect(session.version == 5)
        #expect(model.notice == .saved)
        #expect(model.edited == nil)
    }

    @Test func theNameComesFromTheSavedRuleWhenThePhoneGaveNone() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [anHour]))]
        let (model, _, fake) = await setup(script, displayName: nil)

        #expect(model.name == "Roblox")
        model.setDailyLimitMinutes(60)
        await model.save()

        #expect(await fake.appPolicyWrites.first?.value.displayName == "Roblox")
    }

    @Test func aConflictShowsTheLatestAndDoesNotResend() async {
        let elsewhere = appPolicy(roblox, name: "Roblox", mode: .alwaysBlocked)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine])), .success(snapshot(version: 8, apps: [elsewhere]))]
        script.appPolicy = [.failure(conflict)]
        let (model, session, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        await model.save()

        #expect(model.notice == .conflict)
        #expect(session.version == 8)
        #expect(model.policy == elsewhere)
        #expect(!model.canSave)
        #expect(await fake.appPolicyWrites.count == 1)
    }

    // Review Focus 2.
    @Test func aRuleChangedOnAnotherPhoneIsNeverWrittenOver() async {
        let elsewhere = appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 90)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine])), .success(snapshot(version: 6, apps: [elsewhere]))]
        let (model, session, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        await session.reload()
        #expect(model.policy?.dailyLimitMinutes == 60)
        await model.save()

        #expect(await fake.appPolicyWrites.isEmpty)
        #expect(model.notice == .conflict)
        #expect(model.policy == elsewhere)
        #expect(!model.canSave)
    }

    // Review Focus 2.
    @Test func aNewAppGivenARuleOnAnotherPhoneIsNeverWrittenOver() async {
        let elsewhere = appPolicy(roblox, name: "Roblox", mode: .alwaysBlocked)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 6, apps: [elsewhere]))]
        let (model, session, fake) = await setup(script)
        model.setMode(.dailyLimit)

        await session.reload()
        await model.save()

        #expect(await fake.appPolicyWrites.isEmpty)
        #expect(model.notice == .conflict)
        #expect(model.policy == elsewhere)
        #expect(model.modes.contains(.alwaysBlocked))
    }

    @Test func aNewAppUntouchedThatGotARuleElsewhereHasNothingToSave() async {
        let elsewhere = appPolicy(roblox, name: "Roblox", mode: .alwaysBlocked)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 6, apps: [elsewhere]))]
        let (model, session, fake) = await setup(script)
        #expect(model.canSave)

        await session.reload()
        #expect(!model.canSave)
        await model.save()

        #expect(await fake.appPolicyWrites.isEmpty)
        #expect(model.policy == elsewhere)
    }

    @Test func theSameWindowsInAnotherOrderAreNoConflict() async {
        let evening = BlockWindow(start: ClockTime(hour: 19, minute: 0), end: ClockTime(hour: 21, minute: 0), days: [6, 7])
        let before = appPolicy(roblox, name: "Roblox", mode: .scheduleBlock, windows: [schoolHours, evening])
        let reordered = appPolicy(roblox, name: "Roblox", mode: .scheduleBlock, windows: [evening, schoolHours])
        let later = BlockWindow(start: ClockTime(hour: 9, minute: 0), end: schoolHours.end, days: schoolHours.days)
        let sent = appPolicy(roblox, name: "Roblox", mode: .scheduleBlock, windows: [later, evening])
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [before])), .success(snapshot(version: 5, apps: [reordered]))]
        script.appPolicy = [.success(snapshot(version: 6, apps: [sent]))]
        let (model, session, fake) = await setup(script)
        model.setWindowStart(ClockTime(hour: 9, minute: 0))

        await session.reload()
        await model.save()

        #expect(await fake.appPolicyWrites.count == 1)
        #expect(model.notice == .saved)
    }

    @Test func theSameDaysInAnotherOrderAreNoChangeAndNoConflict() async {
        let before = appPolicy(roblox, name: "Roblox", mode: .scheduleBlock, windows: [schoolHours])
        let shuffled = BlockWindow(start: schoolHours.start, end: schoolHours.end, days: [5, 4, 3, 2, 1])
        let after = appPolicy(roblox, name: "Roblox", mode: .scheduleBlock, windows: [shuffled])
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [before])), .success(snapshot(version: 5, apps: [after]))]
        script.appPolicy = [.success(snapshot(version: 6, apps: [after]))]
        let (model, session, fake) = await setup(script)
        model.setWindowStart(ClockTime(hour: 9, minute: 0))
        await session.reload()
        await model.save()
        #expect(await fake.appPolicyWrites.count == 1)
        #expect(model.notice == .saved)

        var quiet = FakeFamily.Script()
        quiet.rules = [.success(snapshot(version: 4, apps: [before])), .success(snapshot(version: 5, apps: [after]))]
        let (idle, idleSession, _) = await setup(quiet)
        await idleSession.reload()
        #expect(!idle.hasChange)
        #expect(!idle.canSave)
    }

    @Test func onlyTheNameChangingIsNoChangeAndNoConflict() async {
        let before = appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 30)
        let renamed = appPolicy(roblox, name: "Roblox Lite", mode: .dailyLimit, minutes: 30)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [before])), .success(snapshot(version: 5, apps: [renamed]))]
        script.appPolicy = [.success(snapshot(version: 6, apps: [anHour]))]
        let (model, session, fake) = await setup(script)
        model.setDailyLimitMinutes(60)
        await session.reload()
        await model.save()
        #expect(await fake.appPolicyWrites.count == 1)
        #expect(model.notice == .saved)

        var quiet = FakeFamily.Script()
        quiet.rules = [.success(snapshot(version: 4, apps: [before])), .success(snapshot(version: 5, apps: [renamed]))]
        let (idle, idleSession, _) = await setup(quiet)
        await idleSession.reload()
        #expect(!idle.hasChange)
        #expect(!idle.canSave)
    }

    @Test func aNewAppCanBeClosedForGood() async {
        let closed = appPolicy(roblox, name: "Roblox", mode: .alwaysBlocked)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [closed]))]
        let (model, _, fake) = await setup(script)

        #expect(model.modes.contains(.alwaysBlocked))
        model.setMode(.alwaysBlocked)
        #expect(model.selectedMode == .alwaysBlocked)
        await model.save()

        let writes = await fake.appPolicyWrites
        #expect(writes.count == 1)
        #expect(writes.first?.value.mode == .alwaysBlocked)
        #expect(writes.first?.value.dailyLimitMinutes == nil)
        #expect(writes.first?.value.blockWindows.isEmpty == true)
        #expect(model.notice == .saved)
    }

    @Test func aDailyLimitRuleCanBeSwitchedToAlwaysClosed() async {
        let closed = appPolicy(roblox, name: "Roblox", mode: .alwaysBlocked)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [closed]))]
        let (model, _, fake) = await setup(script)

        model.setMode(.alwaysBlocked)
        #expect(model.canSave)
        await model.save()

        #expect(await fake.appPolicyWrites == [RuleWrite(value: closed, version: 4)])
        #expect(model.notice == .saved)
    }

    @Test func aNeverBlockedAppOffersOnlyNoLimit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, neverBlocked: [roblox]))]
        let (model, _, _) = await setup(script)

        #expect(model.modes == [.unrestricted])
    }

    // Review Focus 3.
    @Test func anotherAppsRuleSavedMeanwhileIsNoConflict() async {
        let telegram = appPolicy("org.telegram.messenger", name: "Telegram", mode: .scheduleBlock, windows: [schoolHours])
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.appPolicy = [
            .success(snapshot(version: 5, apps: [mine, telegram])),
            .success(snapshot(version: 6, apps: [anHour, telegram])),
        ]
        let (model, session, fake) = await setup(script)
        let other = AppRuleModel(session: session, packageId: "org.telegram.messenger", displayName: "Telegram")
        model.setDailyLimitMinutes(60)
        other.setMode(.scheduleBlock)

        await other.save()
        await model.save()

        #expect(other.notice == .saved)
        #expect(model.notice == .saved)
        #expect(await fake.appPolicyWrites.map(\.version) == [4, 5])
        #expect(await fake.appPolicyWrites.last?.value == anHour)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
        #expect(session.version == 6)
    }

    // Review Focus 3.
    @Test func aBedtimeSavedMeanwhileIsNoConflict() async {
        let later = BedtimeSchedule(start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 7, minute: 0), windDownMinutes: 30, activeDays: [1, 2, 3, 4, 5, 6, 7])
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.bedtime = [.success(snapshot(version: 5, bedtime: later, apps: [mine]))]
        script.appPolicy = [.success(snapshot(version: 6, bedtime: later, apps: [anHour]))]
        let (model, session, fake) = await setup(script)
        let bedtime = BedtimeModel(session: session)
        model.setDailyLimitMinutes(60)
        bedtime.setStart(ClockTime(hour: 21, minute: 0))

        await bedtime.save()
        await model.save()

        #expect(bedtime.notice == .saved)
        #expect(model.notice == .saved)
        #expect(await fake.appPolicyWrites == [RuleWrite(value: anHour, version: 5)])
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func aFailedSaveKeepsTheEditForAnotherTry() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.appPolicy = [
            .failure(.server(status: 500, error: ApiError(code: .internalError))),
            .failure(.server(status: 403, error: ApiError(code: .childNotActive))),
            .failure(.server(status: 400, error: ApiError(code: .validationFailed))),
        ]
        let (model, _, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        await model.save()
        #expect(model.message == .serverProblem)
        #expect(model.policy?.dailyLimitMinutes == 60)
        #expect(model.canSave)

        await model.save()
        #expect(model.message == .childNotActive)

        await model.save()
        #expect(model.message == .invalidRequest)
        #expect(model.notice == nil)
        #expect(model.canSave)
        #expect(await fake.appPolicyWrites.count == 3)
    }

    @Test func aCancelledSaveSaysNothingAndKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.cancelNextWrite = true
        let (model, session, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        await model.save()

        #expect(model.notice == nil)
        #expect(model.message == nil)
        #expect(model.policy?.dailyLimitMinutes == 60)
        #expect(model.canSave)
        #expect(session.version == 4)
        #expect(await fake.appPolicyWrites.count == 1)
    }

    @Test(.timeLimit(.minutes(5)))
    func twoTapsSaveOnce() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [anHour]))]
        script.writeGate = gate
        let (model, _, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        let first = Task { await model.save() }
        await gate.untilPaused()
        #expect(model.isSaving)
        #expect(!model.canSave)
        await model.save()
        #expect(await fake.appPolicyWrites.count == 1)

        await gate.release()
        await first.value
        #expect(model.notice == .saved)
        #expect(await fake.appPolicyWrites.count == 1)
    }

    @Test(.timeLimit(.minutes(5)))
    func anotherScreensSaveInFlightHoldsThisOneBack() async {
        let gate = PauseGate()
        let later = BedtimeSchedule(start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 7, minute: 0), windDownMinutes: 30, activeDays: [1, 2, 3, 4, 5, 6, 7])
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.bedtime = [.success(snapshot(version: 5, bedtime: later, apps: [mine]))]
        script.appPolicy = [.success(snapshot(version: 6, bedtime: later, apps: [anHour]))]
        script.writeGate = gate
        let (model, session, fake) = await setup(script)
        let bedtime = BedtimeModel(session: session)
        bedtime.setStart(ClockTime(hour: 21, minute: 0))
        model.setDailyLimitMinutes(60)
        #expect(model.canSave)

        let bedtimeSave = Task { await bedtime.save() }
        await gate.untilPaused()
        #expect(!model.canSave)
        await model.save()
        #expect(await fake.appPolicyWrites.isEmpty)

        await gate.release()
        await bedtimeSave.value
        #expect(model.canSave)

        await model.save()
        #expect(await fake.appPolicyWrites.map(\.version) == [5])
        #expect(model.notice == .saved)
    }

    @Test func aFrozenChildCannotSave() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        let (model, _, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        await model.save()

        #expect(!model.canSave)
        #expect(await fake.appPolicyWrites.isEmpty)
    }

    @Test func loadingAgainKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine])), .success(snapshot(version: 4, apps: [mine]))]
        let (model, _, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        await model.load()

        #expect(model.policy?.dailyLimitMinutes == 60)
        #expect(model.canSave)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func nothingIsShownOrSavedBeforeTheRulesArrive() async {
        var script = FakeFamily.Script()
        script.rules = [.failure(offline)]
        let (model, session, fake) = await setup(script)

        #expect(session.loadFailure == .noConnection)
        #expect(model.policy == nil)
        #expect(!model.canSave)
        model.setMode(.dailyLimit)
        await model.save()
        #expect(await fake.appPolicyWrites.isEmpty)
    }
}
