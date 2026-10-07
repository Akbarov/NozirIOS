import Foundation
import NozirInsights
import NozirL10n

/// P17 and its Home row in words (Android `ExtraTimeRequestRow`,
/// `TimeRequestHeaderCard`, `TimeRequestContextCard`, `TimeRequestActions`,
/// `TimeRequestNoteCard`, `TimeRequestAnsweredCard`). A blank name reads as
/// "the child"; a bedtime ask never borrows the minutes' sentence, so every
/// button says what a yes does.
enum TimeRequestTexts {
    private static func name(_ request: ExtraTimeRequest) -> String? {
        LocationTexts.present(request.childName)
    }

    private static func isDelay(_ request: ExtraTimeRequest) -> Bool {
        request.kind == .bedtimeDelay
    }

    static func rowTitle(_ request: ExtraTimeRequest, _ l10n: L10n) -> String {
        isDelay(request) ? l10n.homeBedtimeDelayTitle : l10n.homeExtraTimeTitle
    }

    static func rowBody(_ request: ExtraTimeRequest, _ l10n: L10n) -> String {
        let minutes = request.requestedMinutes
        if isDelay(request) {
            return name(request).map { l10n.homeBedtimeDelayBody($0, minutes) } ?? l10n.homeBedtimeDelayBodyUnnamed(minutes)
        }
        return name(request).map { l10n.homeExtraTimeBody($0, minutes) } ?? l10n.homeExtraTimeBodyUnnamed(minutes)
    }

    static func header(_ request: ExtraTimeRequest, _ l10n: L10n) -> String {
        let minutes = request.requestedMinutes
        if isDelay(request) {
            return name(request).map { l10n.timeRequestHeaderDelay($0, minutes) } ?? l10n.timeRequestHeaderDelayUnnamed(minutes)
        }
        return name(request).map { l10n.timeRequestHeader($0, minutes) } ?? l10n.timeRequestHeaderUnnamed(minutes)
    }

    /// The time the ask was made, on the phone's clock.
    static func headerMeta(_ request: ExtraTimeRequest, _ l10n: L10n, calendar: Calendar = .current) -> String {
        l10n.timeRequestHeaderMeta(DateTexts.timeOfDay(request.createdAt, calendar: calendar))
    }

    /// The child's words, quoted and otherwise untouched.
    static func reason(_ request: ExtraTimeRequest, _ l10n: L10n) -> String {
        LocationTexts.present(request.reason).map { l10n.timeRequestReasonQuoted($0) } ?? l10n.timeRequestReasonEmpty
    }

    /// Two plain facts and no verdict; nil when neither is known.
    static func context(usedMinutesToday: Int?, requestsInLastSevenDays: Int?, _ l10n: L10n) -> String? {
        var sentences: [String] = []
        if let used = usedMinutesToday {
            sentences.append(l10n.timeRequestContextUsed(Durations.short(used, l10n)))
        }
        if let week = requestsInLastSevenDays {
            sentences.append(week <= 1 ? l10n.timeRequestContextWeekFirst : l10n.timeRequestContextWeek(week))
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    static func approveTitle(_ request: ExtraTimeRequest, _ l10n: L10n) -> String {
        isDelay(request)
            ? l10n.timeRequestActionApproveDelay(request.requestedMinutes)
            : l10n.timeRequestActionApprove(request.requestedMinutes)
    }

    static func partialTitle(_ minutes: Int, of request: ExtraTimeRequest, _ l10n: L10n) -> String {
        isDelay(request) ? l10n.timeRequestActionPartialDelay(minutes) : l10n.timeRequestActionPartial(minutes)
    }

    /// Why the reason field is worth using; for a bedtime, that a yes is for tonight only.
    static func note(_ request: ExtraTimeRequest, _ l10n: L10n) -> String {
        if isDelay(request) { return l10n.timeRequestDelayNote }
        return name(request).map { l10n.timeRequestNote($0) } ?? l10n.timeRequestNoteUnnamed
    }

    /// The answer once there is one; nil while waiting or for a status this app does not know.
    static func outcome(_ request: ExtraTimeRequest, _ l10n: L10n) -> String? {
        switch request.status {
        case .approved:
            return l10n.timeRequestDoneApproved(request.grantedMinutes ?? request.requestedMinutes)
        case .declined:
            return l10n.timeRequestDoneDeclined
        case .expired:
            return l10n.timeRequestDoneExpired
        case .pending, .unknown:
            return nil
        }
    }

    /// A refusal's reason shown back to the parent, as the child reads it.
    static func decisionNote(_ request: ExtraTimeRequest, _ l10n: L10n) -> String? {
        LocationTexts.present(request.decisionNote).map { l10n.timeRequestReasonQuoted($0) }
    }
}
