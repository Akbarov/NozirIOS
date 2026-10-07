import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let robloxRule = appPolicy("com.roblox.client", name: "Roblox", mode: .scheduleBlock, windows: [schoolHours])
private let telegramFree = appPolicy("org.telegram.messenger", name: "Telegram", mode: .unrestricted)

@MainActor
private func makeModel(_ script: FakeFamily.Script) -> (AppRulesModel, ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    let session = ChildRulesSession(childId: ali.id, family: family)
    return (AppRulesModel(session: session), session, fake)
}

/// P11 as it opens: the session read, then the phone's apps.
@MainActor
private func setup(_ script: FakeFamily.Script) async -> (AppRulesModel, ChildRulesSession, FakeFamily) {
    let (model, session, fake) = makeModel(script)
    await model.load()
    return (model, session, fake)
}

@MainActor
@Suite struct AppRulesModelTests {
    @Test func theRulesAreTheSessionsInTheServersOrder() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [telegramFree, robloxRule]))]
        script.installedApps = [.success([])]
        let (model, _, _) = await setup(script)

        #expect(model.policies == [telegramFree, robloxRule])
    }

    @Test func onlyAppsWithoutAnyRuleAreOfferedAndNeverAProtectedOne() async {
        let duolingo = InstalledApp(packageId: "com.duolingo", displayName: "Duolingo")
        let bucket = InstalledApp(packageId: "nozir.other_apps", displayName: "Others")
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [telegramFree, robloxRule], neverBlocked: [dialerApp.packageId]))]
        script.installedApps = [.success([robloxApp, dialerApp, telegramApp, bucket, duolingo])]
        let (model, _, _) = await setup(script)

        #expect(model.addableApps == [duolingo])
        #expect(model.choose(dialerApp) == nil)
        #expect(model.choose(bucket) == nil)
        #expect(model.choose(robloxApp) == nil)
    }

    @Test func aRuleSavedElsewhereInTheHubTakesTheAppOffTheList() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp, telegramApp])]
        let (model, session, _) = await setup(script)
        #expect(model.addableApps == [robloxApp, telegramApp])

        session.accept(snapshot(version: 5, apps: [robloxRule]))

        #expect(model.policies == [robloxRule])
        #expect(model.addableApps == [telegramApp])
    }

    // Review Focus 5.
    @Test func aFailedAppsLoadSaysSoAndRetries() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.failure(offline), .success([robloxApp])]
        let (model, _, fake) = await setup(script)
        model.toggleChoosing()

        #expect(model.installedApps == nil)
        #expect(model.appsLoadFailure == .noConnection)
        #expect(!model.isLoadingApps)
        #expect(model.addableApps.isEmpty)

        await model.retryApps()

        #expect(model.appsLoadFailure == nil)
        #expect(model.addableApps == [robloxApp])
        #expect(await fake.calls.filter { $0 == "installedApps" }.count == 2)
    }

    @Test func aPhoneThatSentNoAppsYetIsNotAnError() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([])]
        let (model, _, _) = await setup(script)

        #expect(model.installedApps == [])
        #expect(model.appsLoadFailure == nil)
        #expect(model.addableApps.isEmpty)
    }

    @Test func nothingToAddIsKnownOnlyOnceThePhonesAppsAreRead() async {
        var empty = FakeFamily.Script()
        empty.rules = [.success(snapshot(version: 4))]
        empty.installedApps = [.success([])]
        let (none, _, _) = await setup(empty)
        #expect(none.hasNothingToAdd)

        var one = FakeFamily.Script()
        one.rules = [.success(snapshot(version: 4))]
        one.installedApps = [.success([robloxApp])]
        let (some, _, _) = await setup(one)
        #expect(!some.hasNothingToAdd)

        let (unread, _, _) = makeModel(one)
        #expect(!unread.hasNothingToAdd)

        var ruled = FakeFamily.Script()
        ruled.rules = [.success(snapshot(version: 4, apps: [robloxRule]))]
        ruled.installedApps = [.success([robloxApp])]
        let (withRules, _, _) = await setup(ruled)
        #expect(!withRules.hasNothingToAdd)
    }

    @Test func theAppsAreAskedForOnlyOnceTheRulesArrive() async {
        var script = FakeFamily.Script()
        script.rules = [.failure(offline), .success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp])]
        let (model, session, fake) = await setup(script)

        #expect(session.loadFailure == .noConnection)
        #expect(await fake.calls.filter { $0 == "installedApps" }.isEmpty)

        await model.load()

        #expect(model.addableApps == [robloxApp])
    }

    @Test func loadingAgainReadsNothingTwiceAndKeepsTheSearch() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp]), .success([])]
        let (model, _, fake) = await setup(script)
        model.toggleChoosing()
        model.setQuery("rob")

        await model.load()

        #expect(model.isChoosingApp)
        #expect(model.query == "rob")
        #expect(model.shownApps == [robloxApp])
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
        #expect(await fake.calls.filter { $0 == "installedApps" }.count == 1)
    }

    @Test func openingAndClosingThePickerStartsFromNothingTyped() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp, telegramApp])]
        let (model, _, _) = await setup(script)

        model.toggleChoosing()
        #expect(model.isChoosingApp)
        model.setQuery("tel")
        model.toggleChoosing()

        #expect(!model.isChoosingApp)
        #expect(model.query == "")
        model.toggleChoosing()
        #expect(model.query == "")
        #expect(model.shownApps == [robloxApp, telegramApp])
    }

    @Test func theSearchNarrowsTheOfferedApps() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp, telegramApp])]
        let (model, _, _) = await setup(script)
        model.toggleChoosing()

        model.setQuery("GRAM ")
        #expect(model.shownApps == [telegramApp])

        model.setQuery("zzz")
        #expect(model.shownApps.isEmpty)
        #expect(model.addableApps.count == 2)
    }

    @Test func choosingAnAppOpensItsEditorWithItsNameAndClosesThePicker() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp, telegramApp])]
        let (model, _, _) = await setup(script)
        model.toggleChoosing()
        model.setQuery("rob")

        let target = model.choose(robloxApp)

        #expect(target == AppRuleTarget(packageId: "com.roblox.client", displayName: "Roblox"))
        #expect(!model.isChoosingApp)
        #expect(model.query == "")
    }

    @Test func aRuleOpensWithThePhonesNameWhenThereIsOne() async {
        let unnamed = appPolicy("com.roblox.client", mode: .dailyLimit, minutes: 30)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [unnamed, telegramFree]))]
        script.installedApps = [.success([robloxApp])]
        let (model, _, _) = await setup(script)

        #expect(model.open(unnamed) == AppRuleTarget(packageId: "com.roblox.client", displayName: "Roblox"))
        #expect(model.open(telegramFree) == AppRuleTarget(packageId: "org.telegram.messenger", displayName: "Telegram"))
        #expect(model.name(of: unnamed) == "Roblox")
    }

    @Test func pullToRefreshReadsTheRulesAndTheAppsAgain() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 6, apps: [robloxRule]))]
        script.installedApps = [.success([robloxApp]), .success([robloxApp, telegramApp])]
        let (model, session, _) = await setup(script)

        await model.refresh()

        #expect(session.version == 6)
        #expect(model.addableApps == [telegramApp])
    }

    @Test func aFailedRefreshOfTheAppsKeepsTheListShown() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp]), .failure(offline)]
        let (model, _, _) = await setup(script)

        await model.refresh()

        #expect(model.addableApps == [robloxApp])
        #expect(model.appsLoadFailure == nil)
    }

    @Test(.timeLimit(.minutes(5)))
    func aRetryWhileTheAppsAreOnTheirWayAsksOnce() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp])]
        script.installedAppsGate = gate
        let (model, _, fake) = makeModel(script)

        let first = Task { await model.load() }
        await gate.untilPaused()
        #expect(model.isLoadingApps)
        await model.retryApps()
        await gate.release()
        await first.value

        #expect(await fake.calls.filter { $0 == "installedApps" }.count == 1)
        #expect(model.addableApps == [robloxApp])
    }

    @Test func aCancelledAppsLoadSaysNothing() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.cancelNextInstalledApps = true
        let (model, _, _) = await setup(script)

        #expect(model.appsLoadFailure == nil)
        #expect(!model.isLoadingApps)
        #expect(model.installedApps == nil)
    }

    // Controller ruling F4: a refresh read mid-save would be the version that save is checked against.
    @Test(.timeLimit(.minutes(5)))
    func aRefreshWhileASaveIsOnItsWayReadsNothing() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp])]
        script.appPolicy = [.success(snapshot(version: 5, apps: [robloxRule]))]
        script.writeGate = gate
        let (model, session, fake) = await setup(script)
        let childId = ali.id

        let save = Task {
            await session.write { try await fake.setAppPolicy(robloxRule, of: childId, version: 4) }
        }
        await gate.untilPaused()
        #expect(session.isWriting)

        await model.refresh()

        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
        #expect(await fake.calls.filter { $0 == "installedApps" }.count == 1)

        await gate.release()
        #expect(await save.value == .saved)
        #expect(!session.isWriting)
    }
}
