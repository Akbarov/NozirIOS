import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let conflict = ApiFailure.server(status: 409, error: ApiError(code: .conflict))

@MainActor
private func setup(_ script: FakeFamily.Script) -> (ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    return (ChildRulesSession(childId: ali.id, family: family), fake)
}

@MainActor
@Suite struct ChildRulesSessionTests {
    @Test func aFirstLoadReadsTheRulesAndThePlan() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, trust: 30))]
        script.subscription = [.success(Subscription(activeChildId: nil))]
        let (session, fake) = setup(script)

        await session.load()

        #expect(session.childName == "Ali")
        #expect(session.version == 4)
        #expect(session.snapshot?.maxTrustBonusMinutes == 30)
        #expect(!session.isFrozen)
        #expect(!session.isLoading)
        #expect(await fake.calls == ["rules", "subscription"])
    }

    @Test func loadingAgainDoesNotAskAgain() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 5))]
        let (session, fake) = setup(script)

        await session.load()
        await session.load()

        #expect(session.version == 4)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func aFirstLoadThatFailsCanBeRetried() async {
        var script = FakeFamily.Script()
        script.rules = [.failure(offline), .success(snapshot(version: 4))]
        let (session, _) = setup(script)

        await session.load()
        #expect(session.snapshot == nil)
        #expect(session.loadFailure == .noConnection)
        #expect(!session.isOffline)

        await session.load()
        #expect(session.version == 4)
        #expect(session.loadFailure == nil)
    }

    @Test(.timeLimit(.minutes(5)))
    func aRetryAfterAFailedFirstLoadShowsItIsLoading() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.failure(offline)]
        let (session, fake) = setup(script)
        await session.load()
        #expect(session.loadFailure == .noConnection)
        await fake.add {
            $0.rules = [.success(snapshot(version: 4))]
            $0.rulesGate = gate
        }

        let retry = Task { await session.load() }
        await gate.untilPaused()
        #expect(session.loadFailure == nil)
        #expect(session.isLoading)

        await gate.release()
        await retry.value
        #expect(session.version == 4)
        #expect(!session.isLoading)
    }

    @Test func aReloadWithoutAConnectionKeepsWhatIsShown() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .failure(offline), .success(snapshot(version: 6))]
        let (session, _) = setup(script)
        await session.load()

        await session.reload()
        #expect(session.isOffline)
        #expect(session.version == 4)
        #expect(session.loadFailure == nil)

        await session.reload()
        #expect(!session.isOffline)
        #expect(session.version == 6)
    }

    @Test func anotherActiveChildFreezesThisOne() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        let (session, _) = setup(script)

        await session.load()

        #expect(session.isFrozen)
    }

    @Test func anUnknownPlanFreezesNobody() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (session, fake) = setup(script)

        await session.load()

        #expect(!session.isFrozen)
        #expect(await fake.calls.contains("subscription"))
    }

    @Test func makingThisChildActiveUnfreezesIt() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        script.activeChild = [.success(Subscription(activeChildId: ali.id))]
        let (session, fake) = setup(script)
        await session.load()
        #expect(session.isFrozen)

        await session.makeActive()

        #expect(!session.isFrozen)
        #expect(session.message == nil)
        #expect(await fake.childIds.last == ali.id)
    }

    @Test func aRefusedMakeActiveSaysWhyAndStaysFrozen() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        let (session, _) = setup(script)
        await session.load()

        await session.makeActive()

        #expect(session.isFrozen)
        #expect(session.message == .noConnection)
        #expect(!session.isMakingActive)
    }

    @Test func anAnswerOlderThanWhatIsHeldIsIgnored() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (session, _) = setup(script)
        await session.load()

        session.accept(snapshot(version: 6))
        session.accept(snapshot(version: 5))

        #expect(session.version == 6)
    }

    @Test func aBonusAnswerMovesTheVersionAndTheCeilingOnly() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, trust: 45))]
        let (session, _) = setup(script)
        await session.load()

        session.acceptBonus(version: 5, ceiling: 30)

        #expect(session.version == 5)
        #expect(session.snapshot?.screenTime == ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 180, maxDailyBonusMinutes: 30))
        #expect(session.snapshot?.bedtime == defaultBedtime)
        #expect(session.snapshot?.maxTrustBonusMinutes == 45)
    }

    @Test func aBonusAnswerKeepsTheAppRules() async {
        var script = FakeFamily.Script()
        let roblox = appPolicy("com.roblox.client", mode: .dailyLimit, minutes: 45)
        script.rules = [.success(snapshot(version: 4, apps: [roblox], neverBlocked: ["com.android.dialer"]))]
        let (session, _) = setup(script)
        await session.load()

        session.acceptBonus(version: 5, ceiling: 30)

        #expect(session.version == 5)
        #expect(session.snapshot?.appPolicies == [roblox])
        #expect(session.snapshot?.neverBlockedPackages == ["com.android.dialer"])
    }

    @Test(.timeLimit(.minutes(5)))
    func aReadAskedBeforeAWriteLandedIsDropped() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (session, fake) = setup(script)
        await session.load()
        await fake.add {
            $0.rules = [.success(snapshot(version: 4))]
            $0.rulesGate = gate
        }

        let late = Task { await session.reload() }
        await gate.untilPaused()
        session.accept(snapshot(version: 5, trust: 15))
        await gate.release()
        await late.value

        #expect(session.version == 5)
        #expect(session.snapshot?.maxTrustBonusMinutes == 15)
        #expect(!session.isLoading)
    }

    @Test func aWriteHandsItsAnswerToTheSession() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bedtime = [.success(snapshot(version: 5))]
        let (session, fake) = setup(script)
        await session.load()

        let outcome = await session.write { try await session.family.service.setBedtime(defaultBedtime, of: ali.id, version: 4) }

        #expect(outcome == .saved)
        #expect(session.version == 5)
        #expect(await fake.bedtimeWrites.map(\.version) == [4])
    }

    @Test func aConflictReadsAgainAndIsNotResent() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 7))]
        script.bedtime = [.failure(conflict)]
        let (session, fake) = setup(script)
        await session.load()

        let outcome = await session.write { try await session.family.service.setBedtime(defaultBedtime, of: ali.id, version: 4) }

        #expect(outcome == .conflict)
        #expect(session.version == 7)
        #expect(await fake.bedtimeWrites.count == 1)
    }

    @Test func aRefusedWriteKeepsTheVersion() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bedtime = [.failure(.server(status: 403, error: ApiError(code: .childNotActive)))]
        let (session, _) = setup(script)
        await session.load()

        let outcome = await session.write { try await session.family.service.setBedtime(defaultBedtime, of: ali.id, version: 4) }

        #expect(outcome == .failed(.childNotActive))
        #expect(session.version == 4)
    }

    @Test func aCancelledWriteSaysNothing() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (session, _) = setup(script)
        await session.load()

        let outcome = await session.write { () async throws -> RuleSnapshot in throw CancellationError() }

        #expect(outcome == .cancelled)
        #expect(session.version == 4)
        #expect(session.message == nil)
    }

    @Test func aCancelledMakeActiveSaysNothing() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        script.cancelNextActiveChild = true
        let (session, _) = setup(script)
        await session.load()

        await session.makeActive()

        #expect(session.isFrozen)
        #expect(session.message == nil)
        #expect(!session.isMakingActive)
    }

    @Test(.timeLimit(.minutes(5)))
    func aPlanReadAskedBeforeAnActivationDoesNotUndoIt() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        script.activeChild = [.success(Subscription(activeChildId: ali.id))]
        let (session, fake) = setup(script)
        await session.load()
        #expect(session.isFrozen)
        let activation = PauseGate()
        await fake.add {
            $0.activeChildGate = activation
            $0.rules = [.success(snapshot(version: 4))]
            $0.subscription = [.success(Subscription(activeChildId: UUID()))]
            $0.subscriptionGate = gate
        }

        let making = Task { await session.makeActive() }
        await activation.untilPaused()
        let late = Task { await session.reload() }
        await gate.untilPaused()
        await activation.release()
        await making.value
        #expect(!session.isFrozen)
        await gate.release()
        await late.value

        #expect(!session.isFrozen)
    }

    @Test(.timeLimit(.minutes(5)))
    func twoLoadsAtOnceAskOnce() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 5))]
        script.rulesGate = gate
        let (session, fake) = setup(script)

        let first = Task { await session.load() }
        await gate.untilPaused()
        await session.load()
        await gate.release()
        await first.value

        #expect(session.version == 4)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func aCancelledFirstLoadCanBeRetried() async {
        var script = FakeFamily.Script()
        script.cancelNextRules = true
        script.rules = [.success(snapshot(version: 4))]
        let (session, _) = setup(script)

        await session.load()
        #expect(session.snapshot == nil)
        #expect(session.loadFailure == nil)
        #expect(!session.isLoading)

        await session.load()
        #expect(session.version == 4)
    }

    @Test func aSessionIsItsOwnIdentity() {
        let (first, _) = setup(FakeFamily.Script())
        let (second, _) = setup(FakeFamily.Script())

        #expect(first == first)
        #expect(first != second)
        #expect(Set([first, first, second]).count == 2)
    }
}
