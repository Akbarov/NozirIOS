import Foundation
import NozirInsights
import NozirNetworking

/// Answers the pending list and each decision from its own queue, in order (an
/// empty queue is a phone with no connection), and records what was asked.
actor FakeExtraTime: ExtraTimeService {
    struct Decision: Equatable, Sendable {
        let id: UUID
        let outcome: ExtraTimeOutcome
        let grantedMinutes: Int?
        let note: String?
    }

    struct Script: Sendable {
        var pending: [Result<[ExtraTimeRequest], ApiFailure>] = []
        var decide: [Result<ExtraTimeRequest, ApiFailure>] = []
        /// Held once by the next `pending` / `decide` call, after its answer is taken.
        var pendingGate: PauseGate?
        var decideGate: PauseGate?
    }

    private var script: Script
    private(set) var calls: [String] = []
    private(set) var decisions: [Decision] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    func pending() async throws -> [ExtraTimeRequest] {
        calls.append("pending")
        let answer: Result<[ExtraTimeRequest], ApiFailure> = script.pending.isEmpty ? .failure(offline) : script.pending.removeFirst()
        let gate = script.pendingGate
        script.pendingGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }

    func decide(_ id: UUID, outcome: ExtraTimeOutcome, grantedMinutes: Int?, note: String?) async throws -> ExtraTimeRequest {
        calls.append("decide")
        decisions.append(Decision(id: id, outcome: outcome, grantedMinutes: grantedMinutes, note: note))
        let answer: Result<ExtraTimeRequest, ApiFailure> = script.decide.isEmpty ? .failure(offline) : script.decide.removeFirst()
        let gate = script.decideGate
        script.decideGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }
}
