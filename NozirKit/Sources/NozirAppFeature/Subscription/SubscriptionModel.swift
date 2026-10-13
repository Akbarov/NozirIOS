import Foundation
import Observation
import NozirFamily
import NozirL10n

/// P19 (Android `SubscriptionViewModel`): what the family has and what it
/// could have. Plans are read before the state (a paying family still needs
/// them to name its cadence); the parent's role alongside the plans, so a
/// guardian never sees the pay button flash. A payment is opened here and
/// made on Click's page; nothing here grants anything: after the page opens,
/// the state is read every 5 s (60 times) until the server says PRO, and once
/// more on "Toʻlovni tekshirish" and whenever the app comes back.
@MainActor
@Observable
final class SubscriptionModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// No plans on screen and the last load failed: the offer area is the error.
        case failed(UserMessage)
    }

    /// One sentence above the offer; the prices stay.
    enum Note: Equatable {
        case failure(UserMessage)
        case checkoutNotOpened

        func text(_ l10n: L10n) -> String {
            switch self {
            case .failure(let problem): problem.text(l10n)
            case .checkoutNotOpened: l10n.subscriptionCheckoutNotOpened
            }
        }
    }

    /// Android `PaymentWatchIntervalMillis` × `PaymentWatchAttempts`: five minutes.
    static let watchInterval: Duration = .seconds(5)
    static let watchAttempts = 60

    private(set) var phase: Phase = .loading
    private(set) var plans: [SubscriptionPlan] = []
    /// Nil until the server has said.
    private(set) var state: SubscriptionState?
    /// Yearly until the parent picks otherwise.
    private(set) var selectedPeriod: BillingPeriod?
    /// Only the owner may pay (a guardian gets 403); an unread role counts as owner.
    private(set) var isOwner = true
    /// Prices are on screen but the last refresh found no connection.
    private(set) var isOffline = false
    private(set) var message: Note?
    private(set) var isStartingCheckout = false
    /// A page was opened and the plan has not turned PRO yet.
    private(set) var isAwaitingPayment = false
    /// The state turned PRO while a page was open: the payment just landed (not a family that was PRO on entry).
    private(set) var paymentLanded = false
    /// A page waiting to be opened; the view opens it and calls `checkoutOpened`.
    private(set) var checkoutURLToOpen: URL?
    /// The payment watch, kept so a test can wait for it to end.
    @ObservationIgnored private(set) var watch: Task<Void, Never>?

    /// The phone's calendar, for the dates on screen.
    let calendar: Calendar
    private let billing: any BillingService
    private let family: any FamilyService
    private let sleep: @Sendable (Duration) async throws -> Void
    /// Bumped by every load: an older load's answers are dropped.
    @ObservationIgnored private var generation = 0
    /// Bumped by every state read: an older read never overwrites a newer one.
    @ObservationIgnored private var stateReads = 0
    /// The number of the newest read whose answer was applied: older answers never overwrite it.
    @ObservationIgnored private var lastAppliedRead = 0
    @ObservationIgnored private var isChecking = false

    init(
        billing: any BillingService,
        family: any FamilyService,
        calendar: Calendar = PrivacyModel.phoneCalendar,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.billing = billing
        self.family = family
        self.calendar = calendar
        self.sleep = sleep
    }

    // MARK: What the screen draws

    var yearly: SubscriptionPlan? {
        plans.first { $0.period == .yearly }
    }

    var monthly: SubscriptionPlan? {
        plans.first { $0.period == .monthly }
    }

    var selectedPlan: SubscriptionPlan? {
        switch selectedPeriod {
        case .yearly: yearly
        case .monthly: monthly
        case nil: nil
        }
    }

    /// From the yearly plan, else the monthly one.
    var features: [String] {
        (yearly ?? monthly)?.features ?? []
    }

    var plannedChannels: [PaymentChannel] {
        (yearly ?? monthly)?.plannedChannels ?? []
    }

    var payChannel: PaymentChannel? {
        SubscriptionMath.payChannel(selectedPlan)
    }

    /// Nil without two plans to compare: no badge.
    var savingPercent: Int? {
        guard let yearly, let monthly else { return nil }
        return SubscriptionMath.yearlySavingPercent(yearlySom: yearly.priceSom, monthlySom: monthly.priceSom)
    }

    var isActive: Bool {
        state?.isActive == true
    }

    /// The plans and, for the owner, the pay action. Trial and grace still
    /// get the offer; only a paying family does not. Never while the first
    /// load runs: the plans arrive before the state, and the offer must not
    /// show for a family that turns out to be PRO.
    var offersPlans: Bool {
        phase != .loading && !isActive && !plans.isEmpty
    }

    var canPay: Bool {
        offersPlans && isOwner && payChannel != nil && !isStartingCheckout
    }

    /// Which cadence a plan code is, read off the listed plans; nil for a plan no longer sold.
    func period(of planCode: String?) -> BillingPeriod? {
        guard let planCode else { return nil }
        if planCode == yearly?.code { return .yearly }
        if planCode == monthly?.code { return .monthly }
        return nil
    }

    var activePeriod: BillingPeriod? {
        guard case .active(let planCode, _, _)? = state else { return nil }
        return period(of: planCode)
    }

    // MARK: Actions

    func load() async {
        generation += 1
        let mine = generation
        message = nil
        if plans.isEmpty { phase = .loading }
        let billing = self.billing
        let family = self.family
        async let parent = Self.attempt { try await family.me() }
        let listed = await Self.attempt { try await billing.plans() }
        let role = await parent
        guard mine == generation else { return }
        if case .success(let me) = role {
            isOwner = (me.role ?? "OWNER") == "OWNER"
        }
        var failure: (any Error)?
        switch listed {
        case .success(let fresh):
            apply(plans: fresh)
        case .failure(let error):
            failure = error
        }
        let read = await readState()
        guard mine == generation else { return }
        if failure == nil, case .failure(let error)? = read {
            failure = error
        }
        settle(after: failure)
    }

    /// Only a cadence that is on sale can be picked.
    func select(_ period: BillingPeriod) {
        guard plans.contains(where: { $0.period == period }) else { return }
        selectedPeriod = period
        message = nil
    }

    /// One checkout at a time; a second tap while one is in flight does nothing.
    func pay() async {
        guard canPay, let plan = selectedPlan, let channel = payChannel else { return }
        isStartingCheckout = true
        message = nil
        defer { isStartingCheckout = false }
        do {
            let checkout = try await billing.startCheckout(planCode: plan.code, channel: channel)
            checkoutURLToOpen = checkout.checkoutUrl
            isAwaitingPayment = true
            startWatching()
        } catch is CancellationError {
            return
        } catch {
            message = .failure(UserMessage(error))
        }
    }

    /// The view tried to open the page; `accepted` false means nothing took it.
    func checkoutOpened(_ accepted: Bool) {
        checkoutURLToOpen = nil
        guard !accepted else { return }
        isAwaitingPayment = false
        stopWatching()
        message = .checkoutNotOpened
    }

    /// "Toʻlovni tekshirish".
    func checkPayment() async {
        await checkOnce()
    }

    /// Back from Safari (or any other app): iOS paused the watch meanwhile.
    func sceneBecameActive() async {
        await checkOnce()
    }

    /// The screen went away.
    func stopWatching() {
        watch?.cancel()
    }

    /// The screen is back (a tab switch does not pop it) while a payment is
    /// still awaited: watch again, unless a live watch is already running.
    func resumeWatchingIfAwaiting() {
        guard isAwaitingPayment else { return }
        if let watch, !watch.isCancelled { return }
        startWatching()
    }

    // MARK: Inside

    private func apply(plans fresh: [SubscriptionPlan]) {
        plans = fresh
        if let picked = selectedPeriod, fresh.contains(where: { $0.period == picked }) { return }
        selectedPeriod = (yearly ?? monthly)?.period
    }

    private func apply(state fresh: SubscriptionState) {
        state = fresh
        guard fresh.isActive else { return }
        if isAwaitingPayment { paymentLanded = true }
        isAwaitingPayment = false
        stopWatching()
    }

    /// Android `withFailure`: prices on screen survive a lost connection with a
    /// note; any other fault over them is said above them; with no prices the
    /// fault is the screen.
    private func settle(after failure: (any Error)?) {
        guard let failure else {
            isOffline = false
            phase = .ready
            return
        }
        if failure is CancellationError { return }
        let problem = UserMessage(failure)
        if plans.isEmpty {
            isOffline = false
            phase = .failed(problem)
        } else if problem == .noConnection || problem == .timeout {
            isOffline = true
            phase = .ready
        } else {
            isOffline = false
            phase = .ready
            message = .failure(problem)
        }
    }

    /// Reads and applies the state. Nil when a newer answer was applied meanwhile; a failure never overwrites anything.
    @discardableResult
    private func readState() async -> Result<SubscriptionState, any Error>? {
        stateReads += 1
        let mine = stateReads
        do {
            let fresh = try await family.subscription().state
            guard mine > lastAppliedRead else { return nil }
            lastAppliedRead = mine
            apply(state: fresh)
            return .success(fresh)
        } catch {
            guard mine > lastAppliedRead else { return nil }
            return .failure(error)
        }
    }

    /// One read; dropped while another check is running. A failure is silent (Android).
    private func checkOnce() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        await readState()
    }

    private func startWatching() {
        watch?.cancel()
        watch = Task { await self.watchForPayment() }
    }

    private func watchForPayment() async {
        for _ in 0..<Self.watchAttempts {
            do {
                try await sleep(Self.watchInterval)
                try Task.checkCancellation()
            } catch {
                return
            }
            if case .success(let fresh)? = await readState(), fresh.isActive { return }
            if Task.isCancelled { return }
        }
    }

    private nonisolated static func attempt<Value: Sendable>(
        _ work: @Sendable () async throws -> Value
    ) async -> Result<Value, any Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }
}
