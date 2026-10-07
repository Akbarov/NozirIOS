import Foundation
import NozirInsights

/// A `nozir://` link read by hand (Android `pushDeepLinkOf`). Anything
/// unrecognised — map, challenges, subscription, notifications, a bad id, a
/// link from a newer server — is `other`: never a guess and never a crash.
enum NotificationLink: Equatable {
    case sos(UUID)
    case extraTime(UUID)
    /// The id is the child's.
    case protection(UUID)
    /// The id is the summary's; P16a asks the server which day or week it is.
    case summary(UUID)
    /// The id is the child's.
    case appRules(UUID)
    case other

    private static let scheme = "nozir://"

    static func parse(_ deepLink: String?) -> NotificationLink {
        let trimmed = deepLink?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.hasPrefix(scheme) else { return .other }
        var rest = trimmed.dropFirst(scheme.count)
        if let cut = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            rest = rest[..<cut]
        }
        let segments = rest.split(separator: "/").map(String.init)
        guard segments.count == 2, let id = UUID(uuidString: segments[1]) else { return .other }
        switch segments[0] {
        case "sos": return .sos(id)
        case "extra-time": return .extraTime(id)
        case "protection": return .protection(id)
        case "summary": return .summary(id)
        case "app-rules": return .appRules(id)
        default: return .other
        }
    }

    /// Where a tapped row goes on Home's stack (spec D2), or nil: the row is
    /// still marked read, it just leads nowhere.
    static func step(for notification: ParentNotification) -> SignedInView.HomeStep? {
        switch parse(notification.deepLink) {
        case .sos(let sosId):
            guard let childId = notification.childId else { return nil }
            return .sos(ActiveSos(
                sosId: sosId,
                childId: childId,
                childName: notification.childName,
                triggeredAt: notification.occurredAt
            ))
        case .extraTime(let requestId):
            return .timeRequest(requestId, usedMinutesToday: nil)
        case .protection(let childId):
            return .protection(childId)
        case .summary(let summaryId):
            return .summaryLink(summaryId)
        case .appRules(let childId):
            return .rules(childId)
        case .other:
            return nil
        }
    }
}
