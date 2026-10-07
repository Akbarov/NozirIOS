import Foundation
import NozirNetworking
import NozirPrivacy

/// Answers each privacy call from its own queue, in order, and records what
/// was asked. An empty queue answers like a phone with no connection.
actor FakePrivacy: PrivacyService {
    struct Script: Sendable {
        var disclosure: [Result<PrivacyDisclosure, ApiFailure>] = []
        var current: [Result<ErasureRequestStatus?, ApiFailure>] = []
        var request: [Result<ErasureRequest, ApiFailure>] = []
        /// When true the next `requestDeletion` throws `CancellationError` once.
        var cancelNextRequest = false
        /// Held once by the next `disclosure` call, after its answer is taken.
        var disclosureGate: PauseGate?
        /// Held once by the next `requestDeletion` call, after its answer is taken.
        var requestGate: PauseGate?
    }

    private var script: Script
    private(set) var calls: [String] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    /// Holds the next `disclosure` call, for a test that arms it after a first load.
    func holdNextDisclosure(_ gate: PauseGate) {
        script.disclosureGate = gate
    }

    func disclosure() async throws -> PrivacyDisclosure {
        calls.append("disclosure")
        let answer: Result<PrivacyDisclosure, ApiFailure> = script.disclosure.isEmpty ? .failure(offline) : script.disclosure.removeFirst()
        let gate = script.disclosureGate
        script.disclosureGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }

    func currentDeletion() async throws -> ErasureRequestStatus? {
        calls.append("current")
        let answer: Result<ErasureRequestStatus?, ApiFailure> = script.current.isEmpty ? .failure(offline) : script.current.removeFirst()
        return try answer.get()
    }

    func requestDeletion() async throws -> ErasureRequest {
        calls.append("request")
        if script.cancelNextRequest {
            script.cancelNextRequest = false
            throw CancellationError()
        }
        let answer: Result<ErasureRequest, ApiFailure> = script.request.isEmpty ? .failure(offline) : script.request.removeFirst()
        let gate = script.requestGate
        script.requestGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }
}

/// 2026-10-14T10:00:00Z.
let deletionDate = Date(timeIntervalSince1970: 1_791_972_000)

let sampleDisclosure = PrivacyDisclosure(
    documentVersion: "2026-10-01",
    locale: "uz",
    seen: [DisclosureItem(key: "screen_time", text: "Ekran vaqti"), DisclosureItem(key: "location", text: "Joylashuv")],
    notSeen: [DisclosureItem(key: "messages", text: "Xabarlar")]
)

let pendingRequest = ErasureRequestStatus(
    requestId: "r-1",
    status: "PENDING",
    requestedAt: deletionDate.addingTimeInterval(-7 * 86_400),
    executableAt: deletionDate
)

let recordedRequest = ErasureRequest(
    requestId: "r-1",
    requestedAt: deletionDate.addingTimeInterval(-7 * 86_400),
    executableAt: deletionDate
)
