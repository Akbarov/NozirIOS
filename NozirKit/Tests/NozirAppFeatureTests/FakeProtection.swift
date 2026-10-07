import Foundation
import NozirInsights
import NozirNetworking

/// Answers the status and each send from its own queue, in order (an empty
/// queue is a phone with no connection), and records what was asked.
actor FakeProtection: ProtectionService {
    struct Script: Sendable {
        var status: [Result<ProtectionStatus, ApiFailure>] = []
        var send: [Result<Void, ApiFailure>] = []
        /// Held once by the next `status` / `sendInstructions` call, after its answer is taken.
        var statusGate: PauseGate?
        var sendGate: PauseGate?
    }

    private var script: Script
    /// "status", "send".
    private(set) var calls: [String] = []
    /// The kinds of each send, in call order.
    private(set) var sent: [[PermissionKind]] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    func status(childId: UUID) async throws -> ProtectionStatus {
        calls.append("status")
        let answer: Result<ProtectionStatus, ApiFailure> = script.status.isEmpty ? .failure(offline) : script.status.removeFirst()
        let gate = script.statusGate
        script.statusGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }

    func sendInstructions(childId: UUID, kinds: [PermissionKind]) async throws {
        calls.append("send")
        sent.append(kinds)
        let answer: Result<Void, ApiFailure> = script.send.isEmpty ? .failure(offline) : script.send.removeFirst()
        let gate = script.sendGate
        script.sendGate = nil
        if let gate { await gate.pause() }
        try answer.get()
    }
}

func protectionPermission(
    _ kind: PermissionKind,
    _ status: PermissionStatus = .denied,
    revoked: Bool = false,
    key: String? = nil
) -> ProtectionPermission {
    ProtectionPermission(kind: kind, status: status, wasRevoked: revoked, instructionKey: key)
}

/// 2026-10-07T08:00:00Z.
let lastReport = Date(timeIntervalSince1970: 1_791_360_000)

/// A degraded Xiaomi by default: usage access works, autostart switched itself off.
func protectionStatus(
    childId: UUID = UUID(),
    level: ProtectionLevel = .degraded,
    permissions: [ProtectionPermission] = [
        protectionPermission(.usageAccess, .granted),
        protectionPermission(.oemAutostart, revoked: true, key: "oem.xiaomi.autostart"),
    ],
    lastReportAt: Date? = lastReport,
    isStale: Bool = false,
    manufacturer: String = "xiaomi",
    instructionKey: String? = nil
) -> ProtectionStatus {
    ProtectionStatus(
        childId: childId,
        level: level,
        permissions: permissions,
        lastReportAt: lastReportAt,
        isStale: isStale,
        manufacturer: manufacturer,
        instructionKey: instructionKey
    )
}
