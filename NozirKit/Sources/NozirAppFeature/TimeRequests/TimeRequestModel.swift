import Foundation
import Observation
import NozirInsights
import NozirNetworking

/// P17 (Android `TimeRequestViewModel`): one child's ask, found in the pending
/// list (there is no call for one ask), and the parent's one answer. A second
/// tap while the first is in flight does nothing, and nothing is retried. An
/// ask answered elsewhere (409 `ALREADY_DECIDED`) or gone (404) sends the
/// screen back to the list, which then usually says nothing is waiting.
@MainActor
@Observable
final class TimeRequestModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// Not waiting any more (answered by the other parent, expired) or of
        /// a kind this app cannot describe. An answer, not a fault.
        case missing
        case failed(UserMessage)
    }

    /// The most of a decline note that is kept.
    static let noteLimit = 280

    let requestId: UUID
    /// From the child's Home card; nil leaves the "already used" sentence out.
    let usedMinutesToday: Int?
    private(set) var request: ExtraTimeRequest?
    private(set) var phase: Phase = .loading
    /// An ask is on screen but the last refresh found no connection.
    private(set) var isOffline = false
    /// The answer in flight, for the spinner on the button that sent it.
    private(set) var deciding: ExtraTimeOutcome?
    /// A state rather than a sheet: a mis-tap must not turn a refusal into a bare no.
    private(set) var isWritingDecline = false
    private(set) var declineNote = ""
    /// A failure said once; the view sets it back to nil.
    var toast: UserMessage?

    private let service: any ExtraTimeService
    /// Bumped by every load and every answer: an older answer never overwrites a newer state.
    @ObservationIgnored private var generation = 0

    init(requestId: UUID, usedMinutesToday: Int?, service: any ExtraTimeService) {
        self.requestId = requestId
        self.usedMinutesToday = usedMinutesToday
        self.service = service
    }

    var isDeciding: Bool {
        deciding != nil
    }

    /// Waiting, of a kind the app can describe, and no answer in flight.
    var canDecide: Bool {
        guard let request else { return false }
        return request.isAnswerable && deciding == nil
    }

    /// The smaller amount, when there is one worth a button.
    var partialMinutes: Int? {
        request.flatMap { PartialMinutes.of($0) }
    }

    func load() async {
        // An answer on screen is final: the pending list no longer has it, and
        // "nothing waiting" must not replace "15 minutes given" (plan deviation T4).
        if let request, request.status != .pending { return }
        generation += 1
        let mine = generation
        do {
            let waiting = try await service.pending()
            guard mine == generation else { return }
            if let found = waiting.first(where: { $0.id == requestId && $0.isAnswerable }) {
                request = found
                phase = .ready
            } else {
                request = nil
                phase = .missing
                isWritingDecline = false
            }
            isOffline = false
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation else { return }
            let message = UserMessage(error)
            if request == nil {
                phase = .failed(message)
            } else if message == .noConnection || message == .timeout {
                isOffline = true
            } else {
                toast = message
            }
        }
    }

    func approve() async {
        await decide(.approve, grantedMinutes: nil, note: nil)
    }

    func approvePartial() async {
        guard let minutes = partialMinutes else { return }
        await decide(.partial, grantedMinutes: minutes, note: nil)
    }

    func startDecline() {
        guard canDecide else { return }
        isWritingDecline = true
    }

    /// Back to the three answers; what was written stays for a second try.
    func cancelDecline() {
        guard !isDeciding else { return }
        isWritingDecline = false
    }

    func updateDeclineNote(_ text: String) {
        declineNote = String(text.prefix(Self.noteLimit))
    }

    /// A blank note is no note: the child reads a plain "no", not quotes around nothing.
    func confirmDecline() async {
        guard isWritingDecline else { return }
        let note = declineNote.trimmingCharacters(in: .whitespacesAndNewlines)
        await decide(.decline, grantedMinutes: nil, note: note.isEmpty ? nil : note)
    }

    private func decide(_ outcome: ExtraTimeOutcome, grantedMinutes: Int?, note: String?) async {
        guard canDecide, let request else { return }
        deciding = outcome
        defer { deciding = nil }
        do {
            let answered = try await service.decide(request.id, outcome: outcome, grantedMinutes: grantedMinutes, note: note)
            generation += 1
            self.request = answered
            phase = .ready
            isWritingDecline = false
            isOffline = false
        } catch is CancellationError {
            return
        } catch let failure as ApiFailure where failure.code == ApiErrorCode.alreadyDecided || failure.isNotFound {
            // Answered by the other parent, or expired: ask again what is waiting.
            await load()
        } catch {
            toast = UserMessage(error)
        }
    }
}
