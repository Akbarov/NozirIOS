import Foundation
import NozirFamily
import NozirNetworking

let offline = ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue)

struct RuleWrite<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let version: Int64
}

/// Answers each family call from its own queue, in order, and records what was
/// asked. An empty queue answers like a phone with no connection.
actor FakeFamily: FamilyService {
    struct Script: Sendable {
        var children: [Result<[Child], ApiFailure>] = []
        var child: [Result<Child, ApiFailure>] = []
        var create: [Result<Child, ApiFailure>] = []
        var update: [Result<Child, ApiFailure>] = []
        var remove: [Result<Void, ApiFailure>] = []
        var rules: [Result<RuleSnapshot, ApiFailure>] = []
        var screenTime: [Result<RuleSnapshot, ApiFailure>] = []
        var bedtime: [Result<RuleSnapshot, ApiFailure>] = []
        var currentCode: [Result<PairingCode?, ApiFailure>] = []
        var issueCode: [Result<PairingCode, ApiFailure>] = []
        var devices: [Result<[ChildDevice], ApiFailure>] = []
        var subscription: [Result<Subscription, ApiFailure>] = []
        var activeChild: [Result<Subscription, ApiFailure>] = []
        var me: [Result<ParentProfile, ApiFailure>] = []
        var locale: [Result<ParentProfile, ApiFailure>] = []
    }

    private var script: Script
    private(set) var calls: [String] = []
    private(set) var created: [ChildCreate] = []
    private(set) var updates: [ChildUpdate] = []
    private(set) var screenTimeWrites: [RuleWrite<ScreenTimeLimit>] = []
    private(set) var bedtimeWrites: [RuleWrite<BedtimeSchedule>] = []
    private(set) var locales: [String] = []
    /// The child each call was about, in call order.
    private(set) var childIds: [UUID] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    private func next<T>(_ name: String, _ queue: WritableKeyPath<Script, [Result<T, ApiFailure>]>) throws -> T {
        calls.append(name)
        guard !script[keyPath: queue].isEmpty else { throw offline }
        return try script[keyPath: queue].removeFirst().get()
    }

    func children() async throws -> [Child] { try next("children", \.children) }
    func child(_ id: UUID) async throws -> Child {
        childIds.append(id)
        return try next("child", \.child)
    }

    func createChild(_ child: ChildCreate) async throws -> Child {
        created.append(child)
        return try next("create", \.create)
    }

    func updateChild(_ id: UUID, _ update: ChildUpdate) async throws -> Child {
        childIds.append(id)
        updates.append(update)
        return try next("update", \.update)
    }

    func removeChild(_ id: UUID) async throws {
        childIds.append(id)
        try next("remove", \.remove)
    }
    func rules(of childId: UUID) async throws -> RuleSnapshot {
        childIds.append(childId)
        return try next("rules", \.rules)
    }

    func setScreenTime(_ limit: ScreenTimeLimit, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        childIds.append(childId)
        screenTimeWrites.append(RuleWrite(value: limit, version: version))
        return try next("screenTime", \.screenTime)
    }

    func setBedtime(_ bedtime: BedtimeSchedule, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        childIds.append(childId)
        bedtimeWrites.append(RuleWrite(value: bedtime, version: version))
        return try next("bedtime", \.bedtime)
    }

    func currentPairingCode(for childId: UUID) async throws -> PairingCode? {
        childIds.append(childId)
        return try next("currentCode", \.currentCode)
    }
    func issuePairingCode(for childId: UUID) async throws -> PairingCode {
        childIds.append(childId)
        return try next("issueCode", \.issueCode)
    }
    func devices(of childId: UUID) async throws -> [ChildDevice] {
        childIds.append(childId)
        return try next("devices", \.devices)
    }
    func subscription() async throws -> Subscription { try next("subscription", \.subscription) }
    func chooseActiveChild(_ childId: UUID) async throws -> Subscription {
        childIds.append(childId)
        return try next("activeChild", \.activeChild)
    }
    func me() async throws -> ParentProfile { try next("me", \.me) }

    func updateLocale(_ locale: String) async throws -> ParentProfile {
        locales.append(locale)
        return try next("locale", \.locale)
    }
}

func makeChild(
    _ name: String = "Ali",
    id: UUID = UUID(),
    birthYear: Int = 2015,
    phone: String? = nil,
    avatar: String? = "teal",
    state: PairingState = .notPaired
) -> Child {
    Child(id: id, displayName: name, birthYear: birthYear, ageGroup: .explorer, avatarKey: avatar, phoneE164: phone, pairingState: state)
}

let defaultLimit = ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 180, maxDailyBonusMinutes: 60)
let defaultBedtime = BedtimeSchedule(
    start: ClockTime(hour: 22, minute: 0),
    end: ClockTime(hour: 7, minute: 0),
    windDownMinutes: 30,
    activeDays: [1, 2, 3, 4, 5, 6, 7]
)

func snapshot(version: Int64, limit: ScreenTimeLimit = defaultLimit, bedtime: BedtimeSchedule = defaultBedtime) -> RuleSnapshot {
    RuleSnapshot(version: version, screenTime: limit, bedtime: bedtime)
}

func pairingCode(_ code: String = "472918", state: PairingState = .codeIssued) -> PairingCode {
    PairingCode(code: code, expiresAt: Date(timeIntervalSince1970: 1_791_200_000), qrPayload: "nozir://pair?code=\(code)", state: state)
}
