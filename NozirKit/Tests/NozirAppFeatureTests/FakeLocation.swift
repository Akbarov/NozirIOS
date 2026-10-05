import Foundation
import NozirLocation
import NozirNetworking

/// Answers each call from its own script and records what was asked.
/// Locations are a queue per child whose last answer repeats (a phone that has
/// nothing newer keeps giving the same fix); a child with no queue has never
/// reported (404). Other queues answer like a phone with no connection when empty.
actor FakeLocation: LocationService {
    struct Script: Sendable {
        var locations: [UUID: [Result<LocationSnapshot, ApiFailure>]] = [:]
        var requests: [Result<Bool, ApiFailure>] = []
        var zones: [UUID: Result<[SafeZone], ApiFailure>] = [:]
        var create: [Result<SafeZone, ApiFailure>] = []
        var update: [Result<SafeZone, ApiFailure>] = []
        var delete: [Result<Void, ApiFailure>] = []
        var sos: [Result<SosAlertDetail, ApiFailure>] = []
        var acknowledge: [Result<SosAlertDetail, ApiFailure>] = []
    }

    private var script: Script
    private(set) var calls: [String] = []
    private(set) var childIds: [UUID] = []
    private(set) var drafts: [SafeZoneDraft] = []
    private(set) var zoneIds: [UUID] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    func location(of childId: UUID) async throws -> LocationSnapshot {
        calls.append("location")
        childIds.append(childId)
        guard var queue = script.locations[childId], let first = queue.first else { throw notFound }
        if queue.count > 1 {
            queue.removeFirst()
            script.locations[childId] = queue
        }
        return try first.get()
    }

    func requestLocation(of childId: UUID) async throws -> Bool {
        calls.append("request")
        childIds.append(childId)
        guard !script.requests.isEmpty else { return true }
        return try script.requests.removeFirst().get()
    }

    func safeZones(of childId: UUID) async throws -> [SafeZone] {
        calls.append("zones")
        childIds.append(childId)
        return try (script.zones[childId] ?? .success([])).get()
    }

    func createSafeZone(_ draft: SafeZoneDraft, for childId: UUID) async throws -> SafeZone {
        calls.append("create")
        childIds.append(childId)
        drafts.append(draft)
        guard !script.create.isEmpty else { throw offline }
        return try script.create.removeFirst().get()
    }

    func updateSafeZone(_ zoneId: UUID, _ draft: SafeZoneDraft) async throws -> SafeZone {
        calls.append("update")
        zoneIds.append(zoneId)
        drafts.append(draft)
        guard !script.update.isEmpty else { throw offline }
        return try script.update.removeFirst().get()
    }

    func deleteSafeZone(_ zoneId: UUID) async throws {
        calls.append("delete")
        zoneIds.append(zoneId)
        guard !script.delete.isEmpty else { throw offline }
        try script.delete.removeFirst().get()
    }

    func sosAlert(_ sosId: UUID) async throws -> SosAlertDetail {
        calls.append("sos")
        guard !script.sos.isEmpty else { throw offline }
        return try script.sos.removeFirst().get()
    }

    func acknowledgeSos(_ sosId: UUID) async throws -> SosAlertDetail {
        calls.append("acknowledge")
        guard !script.acknowledge.isEmpty else { throw offline }
        return try script.acknowledge.removeFirst().get()
    }
}

/// Holds the poll's pause until the test lets it go.
actor PauseGate {
    private var paused = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var held: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        paused += 1
        let ready = waiters
        waiters = []
        ready.forEach { $0.resume() }
        await withCheckedContinuation { held.append($0) }
    }

    /// Returns once some pause is being held.
    func untilPaused() async {
        if !held.isEmpty { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }
}

let baseTime = Date(timeIntervalSince1970: 1_791_300_000)

func fixAt(
    minutesAfter minutes: Double = 0,
    latitude: Double = 41.3111,
    longitude: Double = 69.2797,
    zoneId: UUID? = nil,
    zoneName: String? = nil,
    isStale: Bool = false
) -> LocationSnapshot {
    LocationSnapshot(
        occurredAt: baseTime.addingTimeInterval(minutes * 60),
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: 20,
        zoneId: zoneId,
        zoneName: zoneName,
        batteryPercent: 60,
        isStale: isStale
    )
}

func reasonAt(minutesAfter minutes: Double, _ reason: LocationUnavailableReason = .locationOff) -> LocationSnapshot {
    LocationSnapshot(isStale: true, unavailableReason: reason, unavailableAt: baseTime.addingTimeInterval(minutes * 60))
}

func zone(
    _ name: String = "Maktab",
    for childId: UUID,
    id: UUID = UUID(),
    radius: Int = 200,
    isActive: Bool = true
) -> SafeZone {
    SafeZone(
        id: id,
        childId: childId,
        name: name,
        latitude: 41.30,
        longitude: 69.25,
        radiusMeters: radius,
        notifyOnEnter: true,
        notifyOnExit: false,
        isActive: isActive
    )
}
