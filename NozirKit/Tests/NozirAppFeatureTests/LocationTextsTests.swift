import Foundation
import Testing
import NozirFamily
import NozirL10n
import NozirLocation
@testable import NozirAppFeature

private let now = Date(timeIntervalSince1970: 1_791_300_000)

private var tashkent: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
    return calendar
}

private func fix(zone: String? = nil, place: String? = nil, minutesAgo: Double = 5, accuracy: Double? = 24.6, battery: Int? = 64) -> LocationSnapshot {
    LocationSnapshot(
        occurredAt: now.addingTimeInterval(-minutesAgo * 60),
        latitude: 41.3111,
        longitude: 69.2797,
        accuracyMeters: accuracy,
        zoneName: zone,
        placeLabel: place,
        batteryPercent: battery
    )
}

private func alert(
    name: String? = "Ali",
    status: SosStatus = .active,
    place: String? = nil,
    hasLocation: Bool = true,
    fixMinutesAgo: Double? = 11,
    acknowledgedAt: Date? = nil
) -> SosAlertDetail {
    SosAlertDetail(
        id: UUID(),
        childId: UUID(),
        childName: name,
        triggeredAt: now.addingTimeInterval(-3 * 60),
        status: status,
        latitude: hasLocation ? 41.3111 : nil,
        longitude: hasLocation ? 69.2797 : nil,
        accuracyMeters: 12,
        locationFixAt: fixMinutesAgo.map { now.addingTimeInterval(-$0 * 60) },
        placeLabel: place,
        acknowledgedAt: acknowledgedAt
    )
}

@Suite struct LocationTextsTests {
    private let l10n = L10n(.uz)

    @Test func theHeadlineNamesTheZoneBeforeTheStreet() {
        #expect(LocationTexts.headline(fix(zone: "Maktab", place: "Amir Temur 1"), childName: "Ali", l10n) == l10n.locationChildAtPlace("Ali", "Maktab"))
        #expect(LocationTexts.headline(fix(place: "Amir Temur 1"), childName: "Ali", l10n) == l10n.locationChildAtPlace("Ali", "Amir Temur 1"))
        #expect(LocationTexts.headline(fix(), childName: nil, l10n) == l10n.locationPlaceUnknown)
        #expect(LocationTexts.headline(fix(zone: "  "), childName: nil, l10n) == l10n.locationPlaceUnknown)
    }

    @Test func theFixSaysHowOldAndWhen() {
        let line = LocationTexts.updated(fix(minutesAgo: 5), now: now, l10n, calendar: tashkent)
        let expectedTime = DateTexts.timeOfDay(now.addingTimeInterval(-300), calendar: tashkent)

        #expect(line == l10n.locationUpdatedAt("5 daqiqa oldin", expectedTime))
        #expect(LocationTexts.updated(LocationSnapshot(isStale: true), now: now, l10n) == nil)
    }

    @Test func accuracyAndBatteryAreWholeNumbers() {
        #expect(LocationTexts.accuracy(24.6, l10n) == l10n.locationAccuracy(25))
        #expect(LocationTexts.accuracy(nil, l10n) == nil)
        #expect(LocationTexts.battery(64, l10n) == l10n.locationBattery(64))
        #expect(LocationTexts.battery(nil, l10n) == nil)
    }

    @Test func eachReasonHasItsSentence() {
        #expect(LocationTexts.unavailable(.locationOff, l10n) == l10n.locationUnavailableOff)
        #expect(LocationTexts.unavailable(.permissionDenied, l10n) == l10n.locationUnavailablePermission)
        #expect(LocationTexts.unavailable(.noFix, l10n) == l10n.locationUnavailableNoFix)
        #expect(LocationTexts.unavailableWhen(now.addingTimeInterval(-120), now: now, l10n) == l10n.locationUnavailableWhen("2 daqiqa oldin"))
        #expect(LocationTexts.unavailableWhen(nil, now: now, l10n) == nil)
    }

    @Test func theTrackingRowSaysEveryOrOff() {
        #expect(LocationTexts.tracking(LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100), l10n) == l10n.rulesLinkLocationEvery(15))
        #expect(LocationTexts.tracking(LocationTracking(isEnabled: false, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100), l10n) == l10n.locationTrackingOff)
        #expect(LocationTexts.tracking(nil, l10n) == nil)
    }

    @Test func anInactiveZoneSaysSo() {
        let active = SafeZone(id: UUID(), childId: UUID(), name: "Maktab", latitude: 0, longitude: 0, radiusMeters: 200, notifyOnEnter: true, notifyOnExit: false)
        let inactive = SafeZone(id: UUID(), childId: UUID(), name: "Uy", latitude: 0, longitude: 0, radiusMeters: 200, notifyOnEnter: true, notifyOnExit: false, isActive: false)

        #expect(LocationTexts.zoneChip(active, l10n) == "Maktab")
        #expect(LocationTexts.zoneChip(inactive, l10n) == l10n.homeChildUsageAndPlace("Uy", l10n.iosSafeZoneInactive))
        #expect(L10n(.uz).iosSafeZoneInactive == "Faol emas")
        #expect(L10n(.en).iosSafeZoneInactive == "Inactive")
    }

    @Test func anSosHeaderNamesTheChildOrNot() {
        #expect(LocationTexts.sosTitle(childName: "Ali", l10n) == l10n.sosHeaderTitle("Ali"))
        #expect(LocationTexts.sosTitle(childName: nil, l10n) == l10n.sosHeaderTitleUnnamed)
        let expectedTime = DateTexts.timeOfDay(now.addingTimeInterval(-180), calendar: tashkent)
        #expect(LocationTexts.sosMeta(triggeredAt: alert().triggeredAt, now: now, l10n, calendar: tashkent) == l10n.sosHeaderMeta(expectedTime, "3 daqiqa oldin"))
    }

    @Test func anSosPlaceIsItsNameOrItsCoordinates() {
        #expect(LocationTexts.sosPlace(alert(place: "Maktab"), l10n) == "Maktab")
        #expect(LocationTexts.sosPlace(alert(), l10n) == l10n.sosLocationCoordinates("41.3111", "69.2797"))
        #expect(LocationTexts.sosPlace(alert(hasLocation: false), l10n) == nil)
    }

    @Test func anSosFixIsAgedAndCalledStaleAfterFourHours() {
        let fresh = LocationTexts.sosFixAge(alert(fixMinutesAgo: 11), now: now, l10n, calendar: tashkent)
        let freshTime = DateTexts.timeOfDay(now.addingTimeInterval(-660), calendar: tashkent)
        #expect(fresh?.text == l10n.sosLocationFixTaken(freshTime, "11 daqiqa oldin"))
        #expect(fresh?.isStale == false)

        #expect(LocationTexts.sosFixAge(alert(fixMinutesAgo: 5 * 60), now: now, l10n, calendar: tashkent)?.isStale == true)

        let unknown = LocationTexts.sosFixAge(alert(fixMinutesAgo: nil), now: now, l10n)
        #expect(unknown?.text == l10n.sosLocationFixTimeUnknown)
        #expect(unknown?.isStale == false)

        #expect(LocationTexts.sosFixAge(alert(hasLocation: false, fixMinutesAgo: nil), now: now, l10n) == nil)
    }

    @Test func factsHaveAWordForUnknown() {
        #expect(LocationTexts.sosBattery(31, l10n) == l10n.sosFactBatteryValue(31))
        #expect(LocationTexts.sosBattery(nil, l10n) == l10n.sosFactUnknown)
        #expect(LocationTexts.sosConnection(online: true, l10n) == l10n.sosConnectionOnline)
        #expect(LocationTexts.sosConnection(online: false, l10n) == l10n.sosConnectionOffline)
        #expect(LocationTexts.sosAccuracy(12.4, l10n) == l10n.sosLocationAccuracy(12))
    }

    @Test func aSettledAlarmSaysHow() {
        let seenAt = now.addingTimeInterval(-60)
        let seenTime = DateTexts.timeOfDay(seenAt, calendar: tashkent)

        #expect(LocationTexts.sosSettled(alert(status: .active), l10n, calendar: tashkent) == nil)
        #expect(LocationTexts.sosSettled(alert(status: .unknown), l10n, calendar: tashkent) == nil)
        #expect(LocationTexts.sosSettled(alert(status: .acknowledged, acknowledgedAt: seenAt), l10n, calendar: tashkent) == l10n.sosAcknowledgedNote(seenTime))
        #expect(LocationTexts.sosSettled(alert(status: .acknowledged), l10n, calendar: tashkent) == l10n.sosAcknowledgedNoteNoTime)
        #expect(LocationTexts.sosSettled(alert(status: .cancelledByChild), l10n, calendar: tashkent) == l10n.sosCancelledNote("Ali"))
        #expect(LocationTexts.sosSettled(alert(name: nil, status: .cancelledByChild), l10n, calendar: tashkent) == l10n.sosCancelledNoteUnnamed)
        #expect(LocationTexts.sosSettled(alert(status: .resolved), l10n, calendar: tashkent) == l10n.sosResolvedNote)
    }

    @Test func aRadiusIsWrittenInMetres() {
        #expect(LocationTexts.radius(200, l10n) == l10n.safeZoneRadiusValue(200))
    }
}
