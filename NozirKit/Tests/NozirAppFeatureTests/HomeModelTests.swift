import Foundation
import Testing
import NozirDesignSystem
import NozirFamily
import NozirInsights
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

@MainActor
private func setup(
    _ homes: [Result<ParentHome, ApiFailure>],
    family children: [Child] = []
) -> (HomeModel, FakeInsights, FakeFamily) {
    var script = FakeInsights.Script()
    script.home = homes
    let insights = FakeInsights(script)
    var familyScript = FakeFamily.Script()
    familyScript.children = Array(repeating: .success(children), count: homes.count)
    let family = FakeFamily(familyScript)
    let model = HomeModel(insights: insights, family: FamilyStore(service: family), currentYear: 2026)
    return (model, insights, family)
}

@MainActor
@Suite struct HomeModelTests {
    private let l10n = L10n(.uz)

    @Test func appearingAsksForHomeAndTheFamily() async {
        let (model, insights, family) = setup([.success(parentHome([homeCard()]))])

        await model.appear()

        #expect(await insights.calls == ["home"])
        #expect(await family.calls == ["children"])
        #expect(model.cards.count == 1)
        #expect(model.failure == nil)
        #expect(model.notice == nil)
    }

    @Test func anEmptyFamilyHasNoCards() async {
        let (model, _, _) = setup([.success(parentHome([]))])

        await model.appear()

        #expect(model.home != nil)
        #expect(model.cards.isEmpty)
    }

    @Test func aFirstLoadThatFailsIsAFullError() async {
        let (model, _, _) = setup([.failure(offline)])

        await model.appear()

        #expect(model.home == nil)
        #expect(model.failure == .noConnection)
    }

    @Test func aLaterOfflineLoadKeepsTheLastHomeAndSaysSo() async {
        let first = parentHome([homeCard("Ali")])
        let (model, _, _) = setup([.success(first), .failure(offline)])
        await model.appear()

        await model.load()

        #expect(model.home == first)
        #expect(model.failure == nil)
        #expect(model.notice == .offline)
    }

    @Test func aLaterServerFailureKeepsTheLastHomeWithAMessage() async {
        let first = parentHome([homeCard("Ali")])
        let (model, _, _) = setup([.success(first), .failure(.unexpectedStatus(500))])
        await model.appear()

        await model.load()

        #expect(model.home == first)
        #expect(model.notice == .message(.serverProblem))
    }

    @Test func aGoodLoadClearsTheNotice() async {
        let (model, _, _) = setup([.success(parentHome([])), .failure(offline), .success(parentHome([]))])
        await model.appear()
        await model.load()

        await model.load()

        #expect(model.notice == nil)
    }

    @Test func attentionComesFirstAndTheRestKeepTheServersOrder() async {
        let a = homeCard("A"), b = homeCard("B", attention: true), c = homeCard("C"), d = homeCard("D", attention: true)
        let (model, _, _) = setup([.success(parentHome([a, b, c, d]))])

        await model.appear()

        #expect(model.ordered.map(\.displayName) == ["B", "D", "A", "C"])
    }

    @Test func quietRowsOnlyBesideSomeoneWhoNeedsAttention() async {
        let calm = homeCard("A"), worried = homeCard("B", attention: true)
        let (model, _, _) = setup([.success(parentHome([calm, worried])), .success(parentHome([calm]))])
        await model.appear()

        #expect(model.style(of: worried) == .attention)
        #expect(model.style(of: calm) == .quiet)
        #expect(model.showsAttentionNote)

        await model.load()

        #expect(model.style(of: calm) == .plain)
        #expect(!model.showsAttentionNote)
    }

    @Test func theFilterShowsOneChildAndAppearingAgainShowsEveryone() async {
        let ali = homeCard("Ali"), vali = homeCard("Vali", attention: true)
        let home = parentHome([ali, vali])
        let (model, _, _) = setup([.success(home), .success(home)])
        await model.appear()

        model.filter = ali.id

        #expect(model.visible.map(\.displayName) == ["Ali"])
        #expect(model.style(of: ali) == .plain)
        #expect(!model.showsAttentionNote)

        await model.appear()

        #expect(model.filter == nil)
        #expect(model.visible.count == 2)
    }

    @Test func aFilterForAChildNoLongerThereShowsEveryone() async {
        let (model, _, _) = setup([.success(parentHome([homeCard("Ali"), homeCard("Vali")]))])
        await model.appear()

        model.filter = UUID()

        #expect(model.visible.count == 2)
    }

    @Test func theAgeComesFromTheFamilyList() async {
        let id = UUID()
        let (model, _, _) = setup([.success(parentHome([homeCard("Ali", id: id), homeCard("Vali")]))], family: [makeChild("Ali", id: id, birthYear: 2015)])
        await model.appear()

        #expect(model.age(of: model.cards[0]) == 11)
        #expect(model.nameAndAge(of: model.cards[0], l10n) == l10n.homeChildNameAndAge("Ali", 11))
        #expect(model.age(of: model.cards[1]) == nil)
        #expect(model.nameAndAge(of: model.cards[1], l10n) == "Vali")
    }

    @Test func theUsageLineCarriesThePlaceWhenThereIsOne() {
        #expect(HomeModel.usageAndPlace(homeCard(place: "Maktab", used: 95), l10n) == l10n.homeChildUsageAndPlace(Durations.short(95, l10n), "Maktab"))
        #expect(HomeModel.usageAndPlace(homeCard(place: nil, used: 45), l10n) == Durations.short(45, l10n))
        #expect(HomeModel.usageAndRules(homeCard(used: 45), l10n) == l10n.homeChildUsageAndPlace(Durations.short(45, l10n), l10n.homeChildRulesFollowed))
    }

    // Review Focus 2.
    @Test func anOfflinePhoneNeverShowsAPlace() throws {
        let since = try #require(ISO8601DateFormatter().date(from: "2026-10-05T03:10:00Z"))
        let card = homeCard(online: false, place: "Maktab", since: since, used: 95)

        #expect(HomeModel.usageAndPlace(card, l10n) == l10n.homeChildUsageAndPlace(Durations.short(95, l10n), l10n.homeChildOffline))
        #expect(HomeModel.placeTitle(card, l10n) == l10n.homeChildOffline)
        #expect(HomeModel.placeCaption(card, l10n) == nil)
    }

    @Test func aPlaceTileSaysSinceWhen() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tashkent"))
        let since = try #require(ISO8601DateFormatter().date(from: "2026-10-05T03:10:00Z"))

        #expect(HomeModel.placeTitle(homeCard(place: "Maktab", since: since), l10n) == "Maktab")
        #expect(HomeModel.placeCaption(homeCard(place: "Maktab", since: since), l10n, calendar: calendar) == l10n.homePlaceSince("08:10"))
        #expect(HomeModel.placeTitle(homeCard(place: nil), l10n) == l10n.homePlaceUnknown)
        #expect(HomeModel.placeCaption(homeCard(place: nil), l10n) == nil)
    }

    @Test func theSosIsBuiltFromTheAlarmAndTheFamily() async {
        let id = UUID()
        let sos = ActiveSos(sosId: UUID(), childId: id, childName: nil, triggeredAt: Date())
        let (model, _, _) = setup([.success(parentHome([homeCard("Ali", id: id)], sos: sos))], family: [makeChild("Ali", id: id, phone: "+998901234567")])
        await model.appear()

        let alert = model.sosAlert(emergencyNumber: "112")

        #expect(alert?.childName == "Ali")
        #expect(alert?.childCallURL == URL(string: "tel:+998901234567"))
        #expect(alert?.emergencyNumber == "112")
    }

    @Test func noAlarmNoBanner() async {
        let (model, _, _) = setup([.success(parentHome([homeCard()]))])
        await model.appear()

        #expect(model.sosAlert(emergencyNumber: "112") == nil)
    }

    @Test func statusLevelsMapToTheDesignSystem() {
        #expect(StatusLevel.good.designLevel == .good)
        #expect(StatusLevel.critical.designLevel == .critical)
        #expect(StatusLevel.action.label(l10n) == l10n.statusLabelAction)
    }

    @Test func theSwitcherSaysWhoNeedsAttention() async {
        let (model, _, _) = setup([.success(parentHome([homeCard("Ali", attention: true), homeCard("Vali")]))])
        await model.appear()

        let children = model.switcherChildren(l10n)

        #expect(children.map(\.accessibilityLabel) == [
            l10n.contentDescriptionChildAvatarAttention("Ali"),
            l10n.contentDescriptionChildAvatar("Vali"),
        ])
    }

    @Test(.timeLimit(.minutes(5)))
    func aRetryAfterAFailedFirstLoadShowsTheSpinner() async {
        let insights = GatedHome()
        let model = HomeModel(insights: insights, family: FamilyStore(service: FakeFamily()), currentYear: 2026)
        let first = Task { await model.load() }
        await insights.untilAsked(1)
        await insights.answer(1, .failure(offline))
        await first.value
        #expect(model.failure == .noConnection)

        let retry = Task { await model.load() }
        await insights.untilAsked(2)
        #expect(model.failure == nil)
        #expect(model.home == nil)

        await insights.answer(2, .home(parentHome([homeCard("Ali")])))
        await retry.value
        #expect(model.failure == nil)
        #expect(model.cards.map(\.displayName) == ["Ali"])
    }

    @Test(.timeLimit(.minutes(5)))
    func aCancelledFirstLoadOffersARetry() async {
        let insights = GatedHome()
        let model = HomeModel(insights: insights, family: FamilyStore(service: FakeFamily()), currentYear: 2026)
        let first = Task { await model.load() }
        await insights.untilAsked(1)

        first.cancel()
        await insights.answer(1, .cancelled)
        await first.value

        #expect(model.failure == .noConnection)
    }

    @Test(.timeLimit(.minutes(5)))
    func anOlderAnswerArrivingLastIsDropped() async {
        let insights = GatedHome()
        let model = HomeModel(insights: insights, family: FamilyStore(service: FakeFamily()), currentYear: 2026)
        let older = Task { await model.load() }
        await insights.untilAsked(1)
        let newer = Task { await model.load() }
        await insights.untilAsked(2)

        await insights.answer(2, .home(parentHome([homeCard("Vali")])))
        await newer.value
        await insights.answer(1, .home(parentHome([homeCard("Ali")])))
        await older.value

        #expect(model.cards.map(\.displayName) == ["Vali"])
    }

    @Test(.timeLimit(.minutes(5)))
    func anOlderFailureArrivingLastIsDropped() async {
        let insights = GatedHome()
        let model = HomeModel(insights: insights, family: FamilyStore(service: FakeFamily()), currentYear: 2026)
        let older = Task { await model.load() }
        await insights.untilAsked(1)
        let newer = Task { await model.load() }
        await insights.untilAsked(2)

        await insights.answer(2, .home(parentHome([homeCard("Vali")])))
        await newer.value
        await insights.answer(1, .failure(offline))
        await older.value

        #expect(model.notice == nil)
        #expect(model.failure == nil)
        #expect(model.cards.map(\.displayName) == ["Vali"])
    }

    // P17 rows (D1, T9) and Review Focus 5: one row per answerable ask, for the
    // children the filter shows; an ask of an unknown kind has no row.
    @Test func timeRequestRowsFollowTheFilterAndSkipWhatCannotBeAnswered() async {
        let ali = homeCard("Ali", used: 95)
        let vali = homeCard("Vali", used: 40)
        let forAli = extraTimeAsk(childId: ali.id)
        let unknown = extraTimeAsk(childId: ali.id, kind: .unknown("SCHOOL_TRIP"))
        let forVali = extraTimeAsk(childId: vali.id, name: "Vali", kind: .bedtimeDelay)
        let (model, _, _) = setup([.success(parentHome([ali, vali], requests: [forAli, unknown, forVali]))])

        await model.appear()
        #expect(model.timeRequests == [forAli, forVali])
        #expect(model.usedMinutesToday(of: forAli) == 95)

        model.filter = vali.id
        #expect(model.timeRequests == [forVali])
        #expect(model.usedMinutesToday(of: forVali) == 40)
        #expect(model.usedMinutesToday(of: extraTimeAsk()) == nil)
    }

    // The Home answer carries no childName: the row names the child from Home's own card.
    @Test func aHomeAskIsNamedFromTheChildsCard() async {
        let ali = homeCard("Ali")
        let known = extraTimeAsk(childId: ali.id, name: nil)
        let stranger = extraTimeAsk(childId: UUID(), name: nil)
        let (model, _, _) = setup([.success(parentHome([ali], requests: [known, stranger]))])

        await model.appear()

        #expect(model.timeRequests.map(\.childName) == ["Ali", nil])
    }

    @Test func noHomeNoRows() {
        let (model, _, _) = setup([])

        #expect(model.timeRequests.isEmpty)
    }
}

/// Holds each home request until the test answers it by number (1-based).
private actor GatedHome: InsightsService {
    enum Answer: Sendable {
        case home(ParentHome)
        case failure(ApiFailure)
        case cancelled
    }

    private var waiting: [Int: CheckedContinuation<Answer, Never>] = [:]
    private var count = 0

    func home() async throws -> ParentHome {
        count += 1
        let number = count
        let result = await withCheckedContinuation { waiting[number] = $0 }
        switch result {
        case .home(let home): return home
        case .failure(let failure): throw failure
        case .cancelled: throw CancellationError()
        }
    }

    func answer(_ number: Int, _ result: Answer) {
        waiting.removeValue(forKey: number)?.resume(returning: result)
    }

    /// Returns once request `number` is waiting for its answer.
    func untilAsked(_ number: Int) async {
        while waiting[number] == nil { await Task.yield() }
    }

    func dailySummary(of childId: UUID, on date: LocalDate?) async throws -> InsightSummary { throw offline }
    func weeklySummary(of childId: UUID, weekStart: LocalDate) async throws -> InsightSummary { throw offline }
    func dailyUsage(of childId: UUID, from: LocalDate, to: LocalDate) async throws -> [DailyUsage] { throw offline }
    func appUsage(of childId: UUID, range: UsageRange) async throws -> AppBreakdown { throw offline }
}
