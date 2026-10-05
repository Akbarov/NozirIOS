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
}
