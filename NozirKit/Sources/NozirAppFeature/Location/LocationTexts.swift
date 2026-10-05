import Foundation
import NozirFamily
import NozirL10n
import NozirLocation

/// Every sentence the location and SOS screens build from data, in the parent's
/// language. The place name is the server's or nothing: the app never invents one.
enum LocationTexts {
    // MARK: P13

    /// "Ali · Maktab". The zone the child stands in, else the street the server
    /// resolved, else "address unknown" (Android `LocationFix.headline`).
    static func headline(_ snapshot: LocationSnapshot, childName: String?, _ l10n: L10n) -> String {
        let place = present(snapshot.zoneName) ?? present(snapshot.placeLabel) ?? l10n.locationPlaceUnknown
        guard let childName = present(childName) else { return place }
        return l10n.locationChildAtPlace(childName, place)
    }

    /// "5 daqiqa oldin yangilandi · soat 12:05 da olingan".
    static func updated(_ snapshot: LocationSnapshot, now: Date, _ l10n: L10n, calendar: Calendar = .current) -> String? {
        guard let at = snapshot.occurredAt else { return nil }
        return l10n.locationUpdatedAt(ElapsedTime(from: at, to: now).text(l10n), DateTexts.timeOfDay(at, calendar: calendar))
    }

    static func accuracy(_ meters: Double?, _ l10n: L10n) -> String? {
        meters.map { l10n.locationAccuracy(Int($0.rounded())) }
    }

    static func battery(_ percent: Int?, _ l10n: L10n) -> String? {
        percent.map { l10n.locationBattery($0) }
    }

    static func unavailable(_ reason: LocationUnavailableReason, _ l10n: L10n) -> String {
        switch reason {
        case .locationOff: l10n.locationUnavailableOff
        case .permissionDenied: l10n.locationUnavailablePermission
        case .noFix: l10n.locationUnavailableNoFix
        }
    }

    /// "Telefon javobi: 2 daqiqa oldin".
    static func unavailableWhen(_ at: Date?, now: Date, _ l10n: L10n) -> String? {
        at.map { l10n.locationUnavailableWhen(ElapsedTime(from: $0, to: now).text(l10n)) }
    }

    /// The P12b row's value: "Har 10 daqiqada" or the "off" sentence.
    static func tracking(_ tracking: LocationTracking?, _ l10n: L10n) -> String? {
        guard let tracking else { return nil }
        return tracking.isEnabled ? l10n.rulesLinkLocationEvery(tracking.intervalMinutes) : l10n.locationTrackingOff
    }

    static func radius(_ meters: Int, _ l10n: L10n) -> String {
        l10n.safeZoneRadiusValue(meters)
    }

    /// A zone kept after the plan lapsed says it no longer alerts.
    static func zoneChip(_ zone: SafeZone, _ l10n: L10n) -> String {
        zone.isActive ? zone.name : l10n.homeChildUsageAndPlace(zone.name, l10n.iosSafeZoneInactive)
    }

    // MARK: P15

    static func sosTitle(childName: String?, _ l10n: L10n) -> String {
        present(childName).map(l10n.sosHeaderTitle) ?? l10n.sosHeaderTitleUnnamed
    }

    /// "12:02 · 3 daqiqa oldin".
    static func sosMeta(triggeredAt: Date, now: Date, _ l10n: L10n, calendar: Calendar = .current) -> String {
        l10n.sosHeaderMeta(
            DateTexts.timeOfDay(triggeredAt, calendar: calendar),
            ElapsedTime(from: triggeredAt, to: now).text(l10n)
        )
    }

    /// The place name, else the raw coordinates; nil when there is no position at all.
    static func sosPlace(_ alert: SosAlertDetail, _ l10n: L10n) -> String? {
        guard let coordinate = alert.coordinate else { return nil }
        return present(alert.placeLabel)
            ?? l10n.sosLocationCoordinates(String(coordinate.latitude), String(coordinate.longitude))
    }

    static func sosAccuracy(_ meters: Double?, _ l10n: L10n) -> String? {
        meters.map { l10n.sosLocationAccuracy(Int($0.rounded())) }
    }

    /// "12:01 da olingan · 11 daqiqa oldin". Four hours and more is stale and
    /// says so (colour alone never carries the meaning). A position without a
    /// time says that instead; no position, nothing.
    static func sosFixAge(
        _ alert: SosAlertDetail,
        now: Date,
        _ l10n: L10n,
        calendar: Calendar = .current
    ) -> (text: String, isStale: Bool)? {
        guard alert.coordinate != nil else { return nil }
        guard let fixAt = alert.locationFixAt else { return (l10n.sosLocationFixTimeUnknown, false) }
        let age = ElapsedTime(from: fixAt, to: now)
        let isStale: Bool
        if case .stale = age { isStale = true } else { isStale = false }
        return (l10n.sosLocationFixTaken(DateTexts.timeOfDay(fixAt, calendar: calendar), age.text(l10n)), isStale)
    }

    static func sosBattery(_ percent: Int?, _ l10n: L10n) -> String {
        percent.map { l10n.sosFactBatteryValue($0) } ?? l10n.sosFactUnknown
    }

    static func sosConnection(online: Bool, _ l10n: L10n) -> String {
        online ? l10n.sosConnectionOnline : l10n.sosConnectionOffline
    }

    /// Why there is no "I have seen it" button: the alarm is settled.
    static func sosSettled(_ alert: SosAlertDetail, _ l10n: L10n, calendar: Calendar = .current) -> String? {
        switch alert.status {
        case .active, .unknown:
            return nil
        case .acknowledged:
            return alert.acknowledgedAt.map { l10n.sosAcknowledgedNote(DateTexts.timeOfDay($0, calendar: calendar)) }
                ?? l10n.sosAcknowledgedNoteNoTime
        case .cancelledByChild:
            return present(alert.childName).map(l10n.sosCancelledNote) ?? l10n.sosCancelledNoteUnnamed
        case .resolved:
            return l10n.sosResolvedNote
        }
    }

    static func present(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
