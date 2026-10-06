import Foundation
import Testing
import NozirFamily
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let conflict = ApiFailure.server(status: 409, error: ApiError(code: .conflict))
private let chess = BonusChallenge(id: UUID(), kind: .unknown("CHESS"), difficulty: .easy, bonusMinutes: 10, requiresParentApproval: false, enabled: true)

@MainActor
private func setup(_ script: FakeFamily.Script) async -> (BonusModel, ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    let session = ChildRulesSession(childId: ali.id, family: family)
    let model = BonusModel(session: session)
    await model.load()
    return (model, session, fake)
}

@MainActor
@Suite struct BonusModelTests {
    @Test func theTasksAreReadAndNothingIsSavedUntilSomethingChanges() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4, challenges: [mathTask, readingTask, exerciseTask, chess]))]
        let (model, _, _) = await setup(script)

        #expect(model.config?.maxDailyBonusMinutes == 60)
        #expect(model.visibleChallenges.map(\.id) == [mathTask.id, readingTask.id, exerciseTask.id])
        #expect(!model.canSave)
    }

    @Test func aToggleChangesOnlyThatTasksSwitch() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4))]
        let (model, _, _) = await setup(script)

        model.setEnabled(readingTask.id, true)

        #expect(model.config?.challenges.map(\.enabled) == [true, true, true])
        #expect(model.config?.challenges[1].bonusMinutes == readingTask.bonusMinutes)
        #expect(model.canSave)

        model.setEnabled(readingTask.id, false)
        #expect(!model.canSave)
    }

    @Test func savingSendsTheWholeConfigOnTheSessionVersionAndMovesTheSession() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4, challenges: [mathTask, readingTask, exerciseTask, chess]))]
        script.setBonus = [.success(bonusConfig(version: 5, ceiling: 30, challenges: [mathTask, readingTask, exerciseTask, chess]))]
        let (model, session, fake) = await setup(script)
        model.setCeiling(30)

        await model.save()

        #expect(await fake.bonusWrites == [RuleWrite(value: bonusConfig(version: 4, ceiling: 30, challenges: [mathTask, readingTask, exerciseTask, chess]), version: 4)])
        #expect(session.version == 5)
        #expect(session.snapshot?.screenTime.maxDailyBonusMinutes == 30)
        #expect(model.notice == .saved)
        #expect(model.config?.maxDailyBonusMinutes == 30)
        #expect(!model.canSave)
    }

    @Test func theLimitSavedAfterwardsNamesTheVersionTheBonusLeft() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4))]
        script.setBonus = [.success(bonusConfig(version: 5, ceiling: 30))]
        script.screenTime = [.success(snapshot(version: 6))]
        let (bonus, session, fake) = await setup(script)
        let dailyLimit = DailyLimitModel(session: session)
        dailyLimit.setSchoolDayMinutes(90)
        bonus.setCeiling(30)

        await bonus.save()
        await dailyLimit.save()

        #expect(dailyLimit.notice == .saved)
        #expect(await fake.screenTimeWrites == [RuleWrite(value: ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 30), version: 5)])
    }

    @Test func aConflictReadsBothAgainAndDoesNotResend() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 7, limit: ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 180, maxDailyBonusMinutes: 90)))]
        script.bonus = [.success(bonusConfig(version: 4)), .success(bonusConfig(version: 7, ceiling: 90))]
        script.setBonus = [.failure(conflict)]
        let (model, session, fake) = await setup(script)
        model.setCeiling(30)

        await model.save()

        #expect(model.notice == .conflict)
        #expect(session.version == 7)
        #expect(model.config?.maxDailyBonusMinutes == 90)
        #expect(!model.canSave)
        #expect(await fake.bonusWrites.count == 1)
        #expect(await fake.calls.filter { $0 == "bonus" }.count == 2)
    }

    @Test func aRefusedSaveKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4))]
        script.setBonus = [.failure(.server(status: 403, error: ApiError(code: .childNotActive)))]
        let (model, session, _) = await setup(script)
        model.setCeiling(30)

        await model.save()

        #expect(model.message == .childNotActive)
        #expect(model.config?.maxDailyBonusMinutes == 30)
        #expect(model.canSave)
        #expect(session.version == 4)
    }

    @Test func aCancelledSaveSaysNothingAndKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4))]
        script.cancelNextWrite = true
        let (model, session, _) = await setup(script)
        model.setCeiling(30)

        await model.save()

        #expect(model.notice == nil)
        #expect(model.message == nil)
        #expect(model.config?.maxDailyBonusMinutes == 30)
        #expect(model.canSave)
        #expect(session.version == 4)
    }

    // Review Focus 4.
    @Test func loadingAgainKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4)), .success(bonusConfig(version: 4))]
        let (model, _, fake) = await setup(script)
        model.setCeiling(90)

        await model.load()

        #expect(model.config?.maxDailyBonusMinutes == 90)
        #expect(model.canSave)
        #expect(await fake.calls.filter { $0 == "bonus" }.count == 1)
    }

    @Test func aConfigNewerThanTheSessionReadsTheSessionAgainSoTheSaveIsNotStale() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 6))]
        script.bonus = [.success(bonusConfig(version: 6))]
        script.setBonus = [.success(bonusConfig(version: 7, ceiling: 30))]
        let (model, session, fake) = await setup(script)
        #expect(session.version == 6)
        model.setCeiling(30)

        await model.save()

        #expect(await fake.bonusWrites.map(\.version) == [6])
        #expect(model.notice == .saved)
        #expect(session.version == 7)
    }

    @Test func aConfigThatCannotBeReadCanBeRetried() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.failure(offline), .success(bonusConfig(version: 4))]
        let (model, _, _) = await setup(script)
        #expect(model.config == nil)
        #expect(model.loadFailure == .noConnection)

        await model.load()

        #expect(model.config != nil)
        #expect(model.loadFailure == nil)
    }

    @Test func aFrozenChildCannotSave() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        script.bonus = [.success(bonusConfig(version: 4))]
        let (model, _, fake) = await setup(script)
        model.setCeiling(30)

        await model.save()

        #expect(!model.canSave)
        #expect(await fake.bonusWrites.isEmpty)
    }
}

@Suite struct BonusTextsTests {
    private let l10n = L10n(.uz)

    @Test func zeroSaysTasksPayNothing() {
        #expect(BonusTexts.ceilingNote(bonusConfig(version: 1, ceiling: 0), l10n) == l10n.bonusCeilingZero)
    }

    @Test func aCeilingBelowTheTasksSaysWhereItStopsThem() {
        // Enabled: math 20 + exercise 30 = 50.
        let note = BonusTexts.ceilingNote(bonusConfig(version: 1, ceiling: 45), l10n)

        #expect(note == l10n.bonusCeilingBinding(Durations.short(50, l10n), Durations.short(45, l10n)))
        #expect(BonusTexts.ceilingNote(bonusConfig(version: 1, ceiling: 60), l10n) == nil)
    }

    @Test func aTaskIsNamedWithItsDifficultyAndWhoApprovesIt() {
        #expect(BonusTexts.name(.math, l10n) == l10n.bonusChallengeMath)
        #expect(BonusTexts.name(.unknown("CHESS"), l10n) == nil)
        #expect(BonusTexts.subtitle(mathTask, l10n) == l10n.bonusChallengeMedium)
        #expect(BonusTexts.subtitle(exerciseTask, l10n) == l10n.bonusChallengeSubtitle(l10n.bonusChallengeHard))
        #expect(BonusTexts.minutes(exerciseTask, l10n) == l10n.bonusChallengeMinutes(Durations.short(30, l10n)))
        #expect(BonusTexts.ceilingValue(60, l10n) == l10n.bonusCeilingValue(Durations.short(60, l10n)))
        #expect(BonusTexts.caption(childName: "Ali", l10n) == l10n.bonusCaptionNamed("Ali"))
        #expect(BonusTexts.caption(childName: nil, l10n) == l10n.bonusCaption)
    }
}
