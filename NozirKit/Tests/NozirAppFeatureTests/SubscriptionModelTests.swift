import Foundation
import Testing
import NozirFamily
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

/// Records every wait and returns at once: five minutes of watching in no time.
private actor Naps {
    private(set) var asked: [Duration] = []

    func take(_ duration: Duration) {
        asked.append(duration)
    }
}

private let owner = ParentProfile(displayName: "Zohid", phoneE164: nil, locale: "uz", role: "OWNER")
private let guardian = ParentProfile(displayName: "Nodira", phoneE164: nil, locale: "uz", role: "GUARDIAN")
private let forbidden = ApiFailure.server(status: 403, error: ApiError(code: .forbidden))
private let upstream = ApiFailure.server(status: 503, error: ApiError(code: .upstreamUnavailable))
private let paidYearly = SubscriptionState.active(planCode: proYearly.code, endsAt: nil, autoRenew: false)

/// Both plans, and the family answering `states` in order.
private func offered(_ states: [SubscriptionState] = [.free]) -> (FakeBilling.Script, FakeFamily.Script) {
    var billing = FakeBilling.Script()
    billing.plans = [.success([proYearly, proMonthly])]
    var family = FakeFamily.Script()
    family.subscription = states.map { .success(familySubscription($0)) }
    return (billing, family)
}

/// By default the watch waits an hour: a test that does not look at it never
/// sees it run, and `stopWatching()` ends it.
@MainActor
private func setup(
    _ billing: FakeBilling.Script,
    _ family: FakeFamily.Script,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3_600)) }
) -> (SubscriptionModel, FakeBilling, FakeFamily) {
    let billingFake = FakeBilling(billing)
    let familyFake = FakeFamily(family)
    let model = SubscriptionModel(billing: billingFake, family: familyFake, sleep: sleep)
    return (model, billingFake, familyFake)
}

private func reads(_ family: FakeFamily) async -> Int {
    await family.calls.filter { $0 == "subscription" }.count
}

@MainActor
@Suite struct SubscriptionModelTests {
    // Spec §5.3: plans first, then the state (the role alongside the plans).
    @Test func theOfferIsLoadedPlansFirst() async {
        let (billing, base) = offered([.trial(endsAt: nil)])
        var family = base
        family.me = [.success(owner)]
        let (model, billingFake, familyFake) = setup(billing, family)
        #expect(model.phase == .loading)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.plans == [proYearly, proMonthly])
        #expect(model.state == .trial(endsAt: nil))
        #expect(model.selectedPeriod == .yearly)
        #expect(model.selectedPlan == proYearly)
        #expect(model.payChannel == .click)
        #expect(model.isOwner)
        #expect(model.offersPlans)
        #expect(model.canPay)
        #expect(model.features == proYearly.features)
        #expect(model.plannedChannels == proYearly.plannedChannels)
        #expect(model.savingPercent == SubscriptionMath.yearlySavingPercent(yearlySom: proYearly.priceSom, monthlySom: proMonthly.priceSom))
        #expect(!model.isOffline)
        #expect(model.message == nil)
        #expect(await billingFake.calls == ["plans"])
        #expect(await familyFake.calls == ["me", "subscription"])
    }

    // Android `withPlans`: the parent's pick survives a refresh while it is still sold.
    @Test func thePickSurvivesARefreshWhileItIsStillSold() async {
        var billing = FakeBilling.Script()
        billing.plans = [.success([proYearly, proMonthly]), .success([proYearly, proMonthly]), .success([proYearly])]
        var family = FakeFamily.Script()
        family.subscription = Array(repeating: .success(familySubscription(.free)), count: 3)
        let (model, _, _) = setup(billing, family)

        await model.load()
        model.select(.monthly)
        #expect(model.selectedPlan == proMonthly)

        await model.load()
        #expect(model.selectedPeriod == .monthly)

        await model.load()
        #expect(model.selectedPeriod == .yearly)
        model.select(.monthly)
        #expect(model.selectedPeriod == .yearly)
    }

    @Test func aMonthlyOnlyOfferIsMonthlyWithoutASaving() async {
        var billing = FakeBilling.Script()
        billing.plans = [.success([proMonthly])]
        var family = FakeFamily.Script()
        family.subscription = [.success(familySubscription(.free))]
        let (model, _, _) = setup(billing, family)

        await model.load()

        #expect(model.yearly == nil)
        #expect(model.selectedPlan == proMonthly)
        #expect(model.savingPercent == nil)
        #expect(model.features == proMonthly.features)
    }

    // Android `withFailure`: prices on screen survive a lost connection, with a note.
    @Test(arguments: [offline, ApiFailure.network(code: URLError.Code.timedOut.rawValue)])
    func losingTheConnectionKeepsThePrices(failure: ApiFailure) async {
        var billing = FakeBilling.Script()
        billing.plans = [.success([proYearly, proMonthly]), .failure(failure), .success([proYearly, proMonthly])]
        var family = FakeFamily.Script()
        family.subscription = Array(repeating: .success(familySubscription(.free)), count: 3)
        let (model, _, _) = setup(billing, family)
        await model.load()

        await model.load()
        #expect(model.isOffline)
        #expect(model.phase == .ready)
        #expect(model.plans == [proYearly, proMonthly])
        #expect(model.message == nil)

        await model.load()
        #expect(!model.isOffline)
    }

    // Plan deviation S4: no plans and an error is the error, with a retry, even when the state read.
    @Test func aFirstLoadWithoutPlansIsAnErrorThatCanBeRetried() async {
        var billing = FakeBilling.Script()
        billing.plans = [.failure(offline), .success([proYearly, proMonthly])]
        var family = FakeFamily.Script()
        family.subscription = [.success(familySubscription(.free)), .success(familySubscription(.free))]
        let (model, _, _) = setup(billing, family)

        await model.load()
        #expect(model.phase == .failed(.noConnection))
        #expect(model.state == .free)
        #expect(!model.isOffline)

        await model.load()
        #expect(model.phase == .ready)
        #expect(model.plans == [proYearly, proMonthly])
    }

    // A server fault over shown prices is said above them, not called offline.
    @Test func aServerFaultOverShownPricesIsSaidAboveThem() async {
        var billing = FakeBilling.Script()
        billing.plans = [.success([proYearly, proMonthly]), .failure(.unexpectedStatus(500)), .success([proYearly, proMonthly])]
        var family = FakeFamily.Script()
        family.subscription = [
            .success(familySubscription(.free)),
            .success(familySubscription(.free)),
            .failure(.unexpectedStatus(500)),
        ]
        let (model, _, _) = setup(billing, family)
        await model.load()

        await model.load()
        #expect(model.message == .failure(.serverProblem))
        #expect(!model.isOffline)
        #expect(model.plans == [proYearly, proMonthly])

        await model.load()
        #expect(model.message == .failure(.serverProblem))
        #expect(model.state == .free)
    }

    @Test(.timeLimit(.minutes(5)))
    func anOlderLoadNeverOverwritesANewerOne() async {
        let gate = PauseGate()
        var billing = FakeBilling.Script()
        billing.plans = [.success([proMonthly]), .success([proYearly, proMonthly])]
        billing.plansGate = gate
        var family = FakeFamily.Script()
        family.subscription = [.success(familySubscription(.free))]
        let (model, _, familyFake) = setup(billing, family)

        let older = Task { await model.load() }
        await gate.untilPaused()
        await model.load()
        await gate.release()
        await older.value

        #expect(model.plans == [proYearly, proMonthly])
        #expect(model.state == .free)
        #expect(await reads(familyFake) == 1)
    }

    // Review Focus 1 (spec D3): a guardian sees the plans, never the pay button.
    @Test func aGuardianIsNotOfferedThePayment() async {
        let (billing, base) = offered()
        var family = base
        family.me = [.success(guardian)]
        let (model, billingFake, _) = setup(billing, family)

        await model.load()
        await model.pay()

        #expect(!model.isOwner)
        #expect(model.offersPlans)
        #expect(!model.canPay)
        #expect(await billingFake.calls == ["plans"])
    }

    // Plan deviation S5: a role that cannot be read still offers it; the server decides.
    @Test func aRoleThatCannotBeReadStillOffersThePayment() async {
        let (billing, base) = offered([.free, .free])
        var family = base
        family.me = [.success(ParentProfile(displayName: nil, phoneE164: nil, locale: "uz"))]
        let (model, _, _) = setup(billing, family)
        await model.load()
        #expect(model.isOwner)

        await model.load()
        #expect(model.isOwner)
    }

    // Spec §6: a family that pays sees its plan, not an offer.
    @Test func aPayingFamilyIsOfferedNothing() async {
        let (billing, family) = offered([paidYearly])
        let (model, billingFake, _) = setup(billing, family)

        await model.load()
        await model.pay()

        #expect(model.isActive)
        #expect(!model.offersPlans)
        #expect(!model.canPay)
        #expect(model.activePeriod == .yearly)
        #expect(model.period(of: proMonthly.code) == .monthly)
        #expect(model.period(of: "retired_plan") == nil)
        #expect(await billingFake.calls == ["plans"])
    }

    @Test func noLiveChannelMeansNoPayment() async {
        var billing = FakeBilling.Script()
        billing.plans = [.success([planFixture(.yearly, priceSom: proYearly.priceSom, available: [])])]
        var family = FakeFamily.Script()
        family.subscription = [.success(familySubscription(.free))]
        let (model, billingFake, _) = setup(billing, family)

        await model.load()
        await model.pay()

        #expect(model.payChannel == nil)
        #expect(!model.canPay)
        #expect(await billingFake.calls == ["plans"])
    }

    // Spec D1/D2: the page goes to Safari and the watch starts.
    @Test func payingOpensThePageAndStartsWatching() async {
        var (billing, family) = offered()
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, billingFake, _) = setup(billing, family)
        await model.load()
        model.select(.monthly)

        await model.pay()

        #expect(await billingFake.checkouts == [CheckoutCall(planCode: proMonthly.code, channel: .click)])
        #expect(model.checkoutURLToOpen == clickCheckout.checkoutUrl)
        #expect(model.isAwaitingPayment)
        #expect(!model.isStartingCheckout)
        #expect(model.message == nil)
        #expect(model.watch != nil)

        model.checkoutOpened(true)
        #expect(model.checkoutURLToOpen == nil)
        #expect(model.isAwaitingPayment)
        model.stopWatching()
    }

    // Review Focus 2: a second tap while the first is in flight does nothing.
    @Test(.timeLimit(.minutes(5)))
    func twoTapsStartOneCheckout() async {
        let gate = PauseGate()
        var (billing, family) = offered()
        billing.checkout = [.success(clickCheckout), .success(clickCheckout)]
        billing.checkoutGate = gate
        family.me = [.success(owner)]
        let (model, billingFake, _) = setup(billing, family)
        await model.load()

        let first = Task { await model.pay() }
        await gate.untilPaused()
        #expect(model.isStartingCheckout)
        #expect(!model.canPay)
        await model.pay()
        await gate.release()
        await first.value

        #expect(await billingFake.checkouts.count == 1)
        #expect(!model.isStartingCheckout)
        model.stopWatching()
    }

    // Spec §3: 403 (not the owner) and 503 (channel off) are said; the prices stay; nothing opens.
    @Test(arguments: [(forbidden, UserMessage.permissionDenied), (upstream, .serviceUnavailable)])
    func aRefusedCheckoutIsSaidAndThePricesStay(failure: ApiFailure, expected: UserMessage) async {
        var (billing, family) = offered()
        billing.checkout = [.failure(failure)]
        family.me = [.success(owner)]
        let (model, _, _) = setup(billing, family)
        await model.load()

        await model.pay()

        #expect(model.message == .failure(expected))
        #expect(model.checkoutURLToOpen == nil)
        #expect(!model.isAwaitingPayment)
        #expect(model.watch == nil)
        #expect(model.plans == [proYearly, proMonthly])
        #expect(model.canPay)

        model.select(.monthly)
        #expect(model.message == nil)
    }

    // Review Focus 4: a page that is not a web page is never opened.
    @Test func anUnreadableCheckoutOpensNothing() async {
        var (billing, family) = offered()
        billing.checkout = [.failure(.decoding("No web page to open"))]
        family.me = [.success(owner)]
        let (model, _, _) = setup(billing, family)
        await model.load()

        await model.pay()

        #expect(model.message == .failure(.unreadableAnswer))
        #expect(model.checkoutURLToOpen == nil)
        #expect(!model.isAwaitingPayment)
    }

    // Review Focus 4 (spec D1): nothing took the page — said, not awaited, not watched.
    @Test(.timeLimit(.minutes(5)))
    func aPageThatDidNotOpenSaysSoAndStopsWatching() async {
        var (billing, family) = offered()
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, familyFake) = setup(billing, family)
        await model.load()
        await model.pay()

        model.checkoutOpened(false)
        await model.watch?.value

        #expect(model.checkoutURLToOpen == nil)
        #expect(!model.isAwaitingPayment)
        #expect(model.message == .checkoutNotOpened)
        #expect(model.message?.text(L10n(.uz)) == L10n(.uz).subscriptionCheckoutNotOpened)
        #expect(await reads(familyFake) == 1)
    }

    // Spec D2: every 5 s; a trial is not money, so only an active plan stops it.
    @Test func theWatchStopsWhenThePaymentLands() async {
        let naps = Naps()
        var (billing, family) = offered([.free, .trial(endsAt: nil), paidYearly])
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, familyFake) = setup(billing, family, sleep: { await naps.take($0) })
        await model.load()

        await model.pay()
        await model.watch?.value

        #expect(await naps.asked == [SubscriptionModel.watchInterval, SubscriptionModel.watchInterval])
        #expect(SubscriptionModel.watchInterval == .seconds(5))
        #expect(model.state == paidYearly)
        #expect(!model.isAwaitingPayment)
        #expect(!model.offersPlans)
        #expect(await reads(familyFake) == 3)
    }

    // Spec D2: five minutes, then silence; "kutilmoqda" and the check button stay.
    @Test func theWatchGivesUpQuietlyAfterFiveMinutes() async {
        let naps = Naps()
        var (billing, family) = offered(Array(repeating: .free, count: 61))
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, familyFake) = setup(billing, family, sleep: { await naps.take($0) })
        await model.load()

        await model.pay()
        await model.watch?.value

        #expect(SubscriptionModel.watchAttempts == 60)
        #expect(await naps.asked.count == 60)
        #expect(await reads(familyFake) == 61)
        #expect(model.isAwaitingPayment)
        #expect(model.message == nil)
        #expect(model.state == .free)
    }

    // Spec §5.3: leaving the screen cancels the watch.
    @Test(.timeLimit(.minutes(5)))
    func leavingTheScreenStopsTheWatch() async {
        let gate = PauseGate()
        var (billing, family) = offered()
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, familyFake) = setup(billing, family, sleep: { _ in await gate.pause() })
        await model.load()
        await model.pay()

        await gate.untilPaused()
        model.stopWatching()
        await gate.release()
        await model.watch?.value

        #expect(await reads(familyFake) == 1)
        #expect(model.isAwaitingPayment)
    }

    // Spec D2: "Toʻlovni tekshirish" reads once; an active plan ends the wait and the watch.
    @Test(.timeLimit(.minutes(5)))
    func checkingByHandReadsOnceAndEndsTheWatch() async {
        var (billing, family) = offered([.free, paidYearly])
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, familyFake) = setup(billing, family)
        await model.load()
        await model.pay()

        await model.checkPayment()
        await model.watch?.value

        #expect(model.state == paidYearly)
        #expect(!model.isAwaitingPayment)
        #expect(model.paymentLanded)
        #expect(await reads(familyFake) == 2)
    }

    // A family that was already PRO on entry is not "just paid": no announcement.
    @Test func aFamilyAlreadyProOnEntryHasNotJustPaid() async {
        let (billing, family) = offered([paidYearly])
        let (model, _, _) = setup(billing, family)
        await model.load()

        #expect(model.isActive)
        #expect(!model.paymentLanded)
    }

    // Review Focus 3 (spec D2): back from Safari, one read at once; a second while it runs is dropped.
    @Test(.timeLimit(.minutes(5)))
    func comingBackToTheAppChecksAtOnce() async {
        let gate = PauseGate()
        var (billing, family) = offered([.free, paidYearly])
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, familyFake) = setup(billing, family)
        await model.load()
        await model.pay()
        await familyFake.add { $0.subscriptionGate = gate }

        let first = Task { await model.sceneBecameActive() }
        await gate.untilPaused()
        await model.checkPayment()
        await gate.release()
        await first.value
        await model.watch?.value

        #expect(await reads(familyFake) == 2)
        #expect(model.state == paidYearly)
        #expect(!model.isAwaitingPayment)
    }

    @Test func aFailedCheckSaysNothingAndKeepsWaiting() async {
        var (billing, family) = offered()
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, _) = setup(billing, family)
        await model.load()
        await model.pay()

        await model.checkPayment()

        #expect(model.isAwaitingPayment)
        #expect(model.message == nil)
        #expect(model.state == .free)
        model.stopWatching()
    }

    // An older read's success is not lost to a newer read that failed.
    @Test(.timeLimit(.minutes(5)))
    func anOlderSuccessSurvivesANewerFailure() async {
        let gate = PauseGate()
        var (billing, family) = offered([paidYearly])
        family.subscription.append(.failure(offline))
        family.subscriptionGate = gate
        family.me = [.success(owner)]
        let (model, _, _) = setup(billing, family)

        let loading = Task { await model.load() }
        await gate.untilPaused()
        await model.checkPayment()
        await gate.release()
        await loading.value

        #expect(model.state == paidYearly)
        #expect(!model.offersPlans)
    }

    // A second payment replaces the watch: one live watch only.
    @Test(.timeLimit(.minutes(5)))
    func aSecondPaymentCancelsTheEarlierWatch() async {
        var (billing, family) = offered()
        billing.checkout = [.success(clickCheckout), .success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, _) = setup(billing, family)
        await model.load()
        await model.pay()
        let earlier = model.watch

        await model.pay()
        let later = model.watch

        #expect(earlier?.isCancelled == true)
        #expect(later?.isCancelled == false)
        model.stopWatching()
        await earlier?.value
        await later?.value
    }

    // A failure older than an applied success says nothing: no banner over fresh state.
    @Test(.timeLimit(.minutes(5)))
    func anOlderFailureIsDroppedAfterANewerSuccess() async {
        let gate = PauseGate()
        var (billing, family) = offered([])
        family.subscription = [.failure(offline), .success(familySubscription(paidYearly))]
        family.subscriptionGate = gate
        family.me = [.success(owner)]
        let (model, _, _) = setup(billing, family)

        let loading = Task { await model.load() }
        await gate.untilPaused()
        await model.checkPayment()
        await gate.release()
        await loading.value

        #expect(model.state == paidYearly)
        #expect(!model.isOffline)
        #expect(model.message == nil)
    }
}
