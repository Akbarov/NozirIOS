import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirLocation

@Suite struct LocationApiTests {
    @Test func aFixReadsTheServersShape() async throws {
        let (api, transport) = locationApi([.ok(fixJSON)])

        let snapshot = try await api.location(of: aliId)

        #expect(snapshot == LocationSnapshot(
            occurredAt: instant("2026-10-06T07:10:00Z"),
            latitude: 41.3111,
            longitude: 69.2797,
            accuracyMeters: 24.6,
            zoneId: zoneId,
            zoneName: "Maktab",
            batteryPercent: 64,
            isStale: false
        ))
        #expect(snapshot.coordinate == Coordinate(latitude: 41.3111, longitude: 69.2797))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == childPath + "/location")
    }

    @Test func aReasonWithoutAPositionHasNoCoordinate() async throws {
        let (api, _) = locationApi([.ok(reasonOnlyJSON)])

        let snapshot = try await api.location(of: aliId)

        #expect(snapshot.coordinate == nil)
        #expect(snapshot.occurredAt == nil)
        #expect(snapshot.isStale)
        #expect(snapshot.unavailableReason == .locationOff)
        #expect(snapshot.unavailableAt == instant("2026-10-06T07:12:00Z"))
    }

    @Test func anUnknownReasonReadsAsNoFix() async throws {
        let (api, _) = locationApi([.ok(#"{"isStale":true,"unavailableReason":"AIRPLANE","unavailableAt":"2026-10-06T07:12:00Z"}"#)])

        #expect(try await api.location(of: aliId).unavailableReason == .noFix)
    }

    @Test func aPhoneThatNeverReportedIsNotFound() async {
        let (api, _) = locationApi([.error(404, code: "NOT_FOUND")])

        do {
            _ = try await api.location(of: aliId)
            Issue.record("expected not found")
        } catch let failure as ApiFailure {
            #expect(failure.isNotFound)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func askingForAFixPostsAndReadsTheAnswer() async throws {
        let (api, transport) = locationApi([.ok(#"{"asked":false}"#)])

        let asked = try await api.requestLocation(of: aliId)

        #expect(!asked)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == childPath + "/location/request")
    }

    @Test func zonesAreReadWithTheirActiveFlag() async throws {
        let (api, transport) = locationApi([.ok("[\(zoneJSON()),\(zoneJSON(active: ""))]")])

        let zones = try await api.safeZones(of: aliId)

        #expect(zones.count == 2)
        #expect(zones[0] == SafeZone(
            id: zoneId,
            childId: aliId,
            name: "Maktab",
            latitude: 41.3111,
            longitude: 69.2797,
            radiusMeters: 200,
            notifyOnEnter: true,
            notifyOnExit: false,
            iconKey: nil,
            isActive: false
        ))
        #expect(zones[1].isActive)
        #expect(await transport.requests.first?.url?.path == childPath + "/safe-zones")
    }

    @Test func aNewZoneIsPostedForTheChild() async throws {
        let (api, transport) = locationApi([.init(status: 201, body: zoneJSON(active: ""))])
        let draft = SafeZoneDraft(name: "Maktab", latitude: 41.3111, longitude: 69.2797, radiusMeters: 200, notifyOnEnter: true, notifyOnExit: false)

        let zone = try await api.createSafeZone(draft, for: aliId)

        #expect(zone.id == zoneId)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == childPath + "/safe-zones")
        let body = try #require(request.bodyObject)
        #expect(Set(body.keys) == ["name", "latitude", "longitude", "radiusMeters", "notifyOnEnter", "notifyOnExit"])
        #expect(body["radiusMeters"] as? Int == 200)
    }

    @Test func anEditIsPutOnTheZone() async throws {
        let (api, transport) = locationApi([.ok(zoneJSON(active: ""))])
        let draft = SafeZoneDraft(name: "Uy", latitude: 41.3, longitude: 69.2, radiusMeters: 300, notifyOnEnter: false, notifyOnExit: true, iconKey: "home")

        _ = try await api.updateSafeZone(zoneId, draft)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/v1/parent/safe-zones/7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f")
        #expect(request.bodyObject?["iconKey"] as? String == "home")
        #expect(request.bodyObject?["notifyOnExit"] as? Bool == true)
    }

    @Test func deletingAZoneSendsNoBody() async throws {
        let (api, transport) = locationApi([.init(status: 204)])

        try await api.deleteSafeZone(zoneId)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/parent/safe-zones/7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f")
        #expect(request.httpBody == nil)
    }

    @Test func anSosAlertReadsTheServersShape() async throws {
        let (api, transport) = locationApi([.ok(sosJSON())])

        let alert = try await api.sosAlert(sosId)

        #expect(alert.id == sosId)
        #expect(alert.childName == "Ali")
        #expect(alert.childPhoneE164 == "+998901234567")
        #expect(alert.status == .active)
        #expect(alert.batteryPercent == 31)
        #expect(alert.deviceOnline)
        #expect(alert.coordinate == Coordinate(latitude: 41.3111, longitude: 69.2797))
        #expect(alert.accuracyMeters == 12)
        #expect(alert.locationFixAt == instant("2026-10-06T06:59:30Z"))
        #expect(alert.placeLabel == nil)
        #expect(alert.acknowledgedAt == nil)
        #expect(await transport.requests.first?.url?.path == "/v1/parent/sos-alerts/5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10")
    }

    @Test func acknowledgingPostsAndReturnsTheSettledAlert() async throws {
        let (api, transport) = locationApi([.ok(sosJSON(status: "ACKNOWLEDGED", acknowledged: #","acknowledgedAt":"2026-10-06T07:03:00Z""#))])

        let alert = try await api.acknowledgeSos(sosId)

        #expect(alert.status == .acknowledged)
        #expect(alert.acknowledgedAt == instant("2026-10-06T07:03:00Z"))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/parent/sos-alerts/5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10/acknowledge")
    }

    @Test func anUnknownStatusIsNotActive() async throws {
        let (api, _) = locationApi([.ok(sosJSON(status: "ESCALATED"))])

        #expect(try await api.sosAlert(sosId).status == .unknown)
    }

    @Test func aZoneBecomesItsOwnDraft() {
        let zone = SafeZone(id: zoneId, childId: aliId, name: "Maktab", latitude: 1, longitude: 2, radiusMeters: 300, notifyOnEnter: false, notifyOnExit: true, iconKey: "school", isActive: true)

        #expect(zone.draft == SafeZoneDraft(name: "Maktab", latitude: 1, longitude: 2, radiusMeters: 300, notifyOnEnter: false, notifyOnExit: true, iconKey: "school"))
    }
}
