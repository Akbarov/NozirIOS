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
    /// Latest wins: `.task(id:)`, the scene coming back and pull to refresh can
    /// overlap, and an answer from a superseded load is dropped.
    @ObservationIgnored private var generation = 0

    init(
        insights: any InsightsService,
        family: FamilyStore,
        currentYear: Int = Gregorian.currentYear
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
        generation += 1
        let mine = generation
        // A retry from the full error shows the spinner while it asks.
        if home == nil { failure = nil }
        do {
            let fresh = try await insights.home()
            guard mine == generation else { return }
            home = fresh
            failure = nil
            notice = nil
        } catch is CancellationError {
            // Nothing on screen to fall back to: offer a retry rather than a spinner nobody drives.
            if mine == generation, home == nil { failure = .noConnection }
            return
        } catch {
            guard mine == generation else { return }
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

    /// The P05 avatar row; VoiceOver hears the attention dot in the label.
    func switcherChildren(_ l10n: L10n) -> [NozirSwitcherChild] {
        cards.map { card in
            NozirSwitcherChild(
                id: card.id,
                name: card.displayName,
                tone: tone(of: card),
                needsAttention: card.needsAttention,
                accessibilityLabel: card.needsAttention
                    ? l10n.contentDescriptionChildAvatarAttention(card.displayName)
                    : l10n.contentDescriptionChildAvatar(card.displayName)
            )
        }
    }

    func sosAlert(emergencyNumber: String?) -> SosAlert? {
        guard let sos = home?.activeSos else { return nil }
        return SosAlert(sos, child: family.child(sos.childId), emergencyNumber: emergencyNumber)
    }

    /// P17 rows: the asks the app can answer, in the server's order, for the
    /// child the filter shows (everyone when it names no child on screen).
    /// Home's asks carry no child name, so a blank one is read off the child's
    /// card; with no card it stays nil (the unnamed sentence).
    var timeRequests: [ExtraTimeRequest] {
        let waiting = (home?.pendingExtraTimeRequests ?? []).filter(\.isAnswerable).map { request in
            guard LocationTexts.present(request.childName) == nil else { return request }
            return request.named(cards.first { $0.id == request.childId }?.displayName)
        }
        guard let filter, cards.contains(where: { $0.id == filter }) else { return waiting }
        return waiting.filter { $0.childId == filter }
    }

    /// Today's minutes from the child's own card, for P17's context line; nil
    /// when that child has no card.
    func usedMinutesToday(of request: ExtraTimeRequest) -> Int? {
        cards.first { $0.id == request.childId }?.usedMinutes
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
