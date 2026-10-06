import Foundation
import Testing
import NozirFamily
import NozirL10n
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let vali = makeChild("Vali")
private let aliLimit = ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 120, maxDailyBonusMinutes: 60)
private let valiLimit = ScreenTimeLimit(schoolDayMinutes: 240, weekendMinutes: 300, maxDailyBonusMinutes: 60)

@MainActor
private func setup(
    _ script: FakeFamily.Script,
    children: [Child] = [ali, vali],
    childId: UUID? = nil,
    picksChild: Bool = true
) -> (RulesHubModel, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    children.forEach(family.replace)
    let hub = RulesHubModel(
        childId: childId,
        picksChild: picksChild,
        family: family,
        makeSession: { ChildRulesSession(childId: $0, family: family) },
        makeDailyLimit: { DailyLimitModel(session: $0) }
    )
    return (hub, fake)
}

@MainActor
@Suite struct RulesHubModelTests {
    @Test func fromProfileItOpensOnTheFirstChildWithTheSwitcher() {
        let (hub, _) = setup(FakeFamily.Script())

        #expect(hub.selectedChildId == ali.id)
        #expect(hub.dailyLimit?.session === hub.session)
        #expect(hub.showsSwitcher)
        #expect(hub.switcherChildren(L10n(.uz)).map(\.name) == ["Ali", "Vali"])
    }

    @Test func fromAChildsDetailsItIsThatChildOnly() {
        let (hub, _) = setup(FakeFamily.Script(), childId: vali.id, picksChild: false)

        #expect(hub.selectedChildId == vali.id)
        #expect(!hub.showsSwitcher)
    }

    @Test func oneChildNeedsNoSwitcher() {
        let (hub, _) = setup(FakeFamily.Script(), children: [ali])

        #expect(!hub.showsSwitcher)
    }

    @Test func noChildrenIsNoChild() {
        let (hub, _) = setup(FakeFamily.Script(), children: [])

        #expect(hub.session == nil)
        #expect(hub.dailyLimit == nil)
    }

    @Test func anotherChildIsAnotherSession() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, limit: aliLimit)), .success(snapshot(version: 9, limit: valiLimit))]
        let (hub, _) = setup(script)
        await hub.load()
        let aliSession = hub.session
        hub.dailyLimit?.setSchoolDayMinutes(60)

        hub.select(vali.id)
        await hub.load()

        #expect(hub.session !== aliSession)
        #expect(hub.session?.childId == vali.id)
        #expect(hub.dailyLimit?.values?.schoolDayMinutes == 240)
        #expect(hub.dailyLimit?.canSave == false)
    }

    @Test func choosingTheSameChildAgainKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, limit: aliLimit))]
        let (hub, _) = setup(script)
        await hub.load()
        hub.dailyLimit?.setSchoolDayMinutes(60)
        let session = hub.session

        hub.select(ali.id)
        hub.select(nil)

        #expect(hub.session === session)
        #expect(hub.dailyLimit?.values?.schoolDayMinutes == 60)
    }

    // Review Focus 3.
    @Test(.timeLimit(.minutes(5)))
    func aLateAnswerForTheFormerChildNeverReachesTheNewOne() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, limit: aliLimit)), .success(snapshot(version: 9, limit: valiLimit))]
        script.rulesGate = gate
        let (hub, fake) = setup(script)

        let aliLoad = Task { await hub.load() }
        await gate.untilPaused()
        hub.select(vali.id)
        await hub.load()
        await gate.release()
        await aliLoad.value

        #expect(hub.session?.childId == vali.id)
        #expect(hub.session?.version == 9)
        #expect(hub.dailyLimit?.values?.schoolDayMinutes == 240)
        #expect(await fake.childIds == [ali.id, vali.id])
    }
}

@Suite struct RuleTextsTests {
    private let l10n = L10n(.uz)

    @Test func theLadderAtZeroIsOff() {
        #expect(RuleTexts.trustValue(0, l10n) == l10n.trustLadderOffValue)
        #expect(RuleTexts.trustNote(0, l10n) == l10n.trustLadderNoteOff)
        #expect(RuleTexts.trustValue(45, l10n) == l10n.trustLadderValue(Durations.short(45, l10n)))
        #expect(RuleTexts.trustNote(60, l10n) == l10n.trustLadderNoteRungs(Durations.short(60, l10n)))
    }

    @Test func theNoticeAndTheSavedLineNameTheChildWhenKnown() {
        #expect(RuleTexts.limitNotice(childName: "Ali", l10n) == l10n.dailyLimitNoticeNamed("Ali"))
        #expect(RuleTexts.limitNotice(childName: nil, l10n) == l10n.dailyLimitNotice)
        #expect(RuleTexts.saved(childName: "Ali", l10n) == l10n.rulesSavedNamed("Ali"))
        #expect(RuleTexts.saved(childName: nil, l10n) == l10n.rulesSaved)
    }

    @Test func theOtherRulesStateEachRuleAsItStands() {
        let rules = snapshot(version: 1, tracking: LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100))

        #expect(RuleTexts.bedtimeRange(rules.bedtime, l10n) == l10n.rulesTimeRange("22:00", "07:00"))
        #expect(RuleTexts.bonusRow(rules, l10n) == l10n.rulesLinkBonusCeiling(Durations.short(60, l10n)))
        #expect(RuleTexts.locationRow(rules.locationTracking, l10n) == l10n.rulesLinkLocationEvery(15))
        #expect(RuleTexts.locationRow(LocationTracking(isEnabled: false, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100), l10n) == l10n.locationTrackingOff)
    }
}
