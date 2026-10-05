import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirInsights
import NozirL10n

/// P05. Asks for home and the family list each time it appears (the age and
/// the phone number live in the family list, not in home). Keeps the last home
/// it had: a later failure becomes a notice above it, never an empty screen.
@MainActor
@Observable
final class HomeModel {
    enum Notice: Equatable {
        case offline
        case message(UserMessage)
    }

    /// Android `MultiChildHome`: the card that needs attention rises; beside it
    /// the others become quiet rows; with no one needing it, every child gets the
    /// same plain card.
    enum CardStyle: Equatable {
        case attention, quiet, plain
    }

    private(set) var home: ParentHome?
    /// Only while there is no home to show.
    private(set) var failure: UserMessage?
    private(set) var notice: Notice?
    /// The P05 avatar filter; nil is "Hammasi".
    var filter: UUID?
    let family: FamilyStore

    private let insights: any InsightsService
    private let currentYear: Int

    init(
        insights: any InsightsService,
        family: FamilyStore,
        currentYear: Int = Calendar.current.component(.year, from: Date())
    ) {
        self.insights = insights
        self.family = family
        self.currentYear = currentYear
    }

    /// Every time P05 is shown: the filter goes back to everyone.
    func appear() async {
        filter = nil
        await load()
    }

    func load() async {
        do {
            let fresh = try await insights.home()
            home = fresh
            failure = nil
            notice = nil
        } catch is CancellationError {
            return
        } catch {
            let message = UserMessage(error)
            if home == nil {
                failure = message
            } else {
                notice = (message == .noConnection || message == .timeout) ? .offline : .message(message)
            }
        }
        // Ages and phone numbers; a failure here keeps the list there was.
        try? await family.refresh()
    }

    var cards: [ChildHomeCard] {
        home?.children ?? []
    }

    /// Those needing attention first, the rest in the server's order: a stable
    /// partition, never a ranking.
    var ordered: [ChildHomeCard] {
        cards.filter(\.needsAttention) + cards.filter { !$0.needsAttention }
    }

    /// The filtered child, or everyone when the filter names no child on screen.
    var visible: [ChildHomeCard] {
        guard let filter, ordered.contains(where: { $0.id == filter }) else { return ordered }
        return ordered.filter { $0.id == filter }
    }

    /// Under the cards: the "not compared" note when someone needs attention,
    /// otherwise the family sentence.
    var showsAttentionNote: Bool {
        visible.contains(where: \.needsAttention)
    }

    func style(of card: ChildHomeCard) -> CardStyle {
        if card.needsAttention { return .attention }
        return showsAttentionNote ? .quiet : .plain
    }

    func age(of card: ChildHomeCard) -> Int? {
        family.child(card.id).map { currentYear - $0.birthYear }
    }

    func nameAndAge(of card: ChildHomeCard, _ l10n: L10n) -> String {
        age(of: card).map { l10n.homeChildNameAndAge(card.displayName, $0) } ?? card.displayName
    }

    func tone(of card: ChildHomeCard) -> AvatarTone {
        .forKey(card.avatarKey, position: cards.firstIndex { $0.id == card.id } ?? 0)
    }

    var switcherChildren: [NozirSwitcherChild] {
        cards.map { NozirSwitcherChild(id: $0.id, name: $0.displayName, tone: tone(of: $0), needsAttention: $0.needsAttention) }
    }

    func sosAlert(emergencyNumber: String?) -> SosAlert? {
        guard let sos = home?.activeSos else { return nil }
        return SosAlert(sos, child: family.child(sos.childId), emergencyNumber: emergencyNumber)
    }

    /// "1s 35d · Maktab". A phone that stopped reporting says so in place of the
    /// place: a stale place is never shown as the current one.
    nonisolated static func usageAndPlace(_ card: ChildHomeCard, _ l10n: L10n) -> String {
        let usage = Durations.short(card.usedMinutes, l10n)
        let place = card.deviceOnline ? card.placeLabel : l10n.homeChildOffline
        return place.map { l10n.homeChildUsageAndPlace(usage, $0) } ?? usage
    }

    /// A quiet row: no news reads as good news.
    nonisolated static func usageAndRules(_ card: ChildHomeCard, _ l10n: L10n) -> String {
        l10n.homeChildUsageAndPlace(Durations.short(card.usedMinutes, l10n), l10n.homeChildRulesFollowed)
    }

    /// The one-child place tile.
    nonisolated static func placeTitle(_ card: ChildHomeCard, _ l10n: L10n) -> String {
        guard card.deviceOnline else { return l10n.homeChildOffline }
        return card.placeLabel ?? l10n.homePlaceUnknown
    }

    nonisolated static func placeCaption(_ card: ChildHomeCard, _ l10n: L10n, calendar: Calendar = .current) -> String? {
        guard card.deviceOnline, card.placeLabel != nil, let since = card.placeSince else { return nil }
        return l10n.homePlaceSince(DateTexts.timeOfDay(since, calendar: calendar))
    }
}
