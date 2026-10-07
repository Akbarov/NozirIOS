import Foundation
import Observation
import NozirInsights
import NozirNetworking

/// P18 (Android `ProtectionViewModel`): one child's protection, and the offer to
/// send the fix steps to the child's phone. A send is one POST: a second tap
/// while it is in flight does nothing, and nothing is retried. A child no
/// longer in the family (404, or 403 `NOT_YOUR_CHILD` from the backend's
/// child-scope guard) is `.missing`, not an error (plan deviation P1).
@MainActor
@Observable
final class ProtectionModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// The child was removed: an answer, not a fault.
        case missing
        case failed(UserMessage)
    }

    let childId: UUID
    /// From the family list; nil reads as "the child".
    let childName: String?
    private(set) var status: ProtectionStatus?
    private(set) var phase: Phase = .loading
    /// A status is on screen but the last refresh found no connection.
    private(set) var isOffline = false
    private(set) var isSending = false
    /// For the rest of this screen's life: a parent who sees nothing change
    /// presses again, and the child's phone gets the same steps twice.
    private(set) var wereInstructionsSent = false
    /// A failure said once; the view sets it back to nil.
    var toast: UserMessage?

    private let service: any ProtectionService
    /// Bumped by every load: an older answer never overwrites a newer one.
    @ObservationIgnored private var generation = 0

    init(childId: UUID, childName: String?, service: any ProtectionService) {
        self.childId = childId
        self.childName = childName
        self.service = service
    }

    /// What "Yuborish" sends; empty hides the fix section.
    var kindsToFix: [PermissionKind] {
        status?.kindsToFix ?? []
    }

    func load() async {
        generation += 1
        let mine = generation
        // A retry from the full error shows the spinner while it asks.
        if status == nil { phase = .loading }
        do {
            let fresh = try await service.status(childId: childId)
            guard mine == generation else { return }
            status = fresh
            phase = .ready
            isOffline = false
        } catch is CancellationError {
            return
        } catch let failure as ApiFailure where failure.isNotFound || failure.code == ApiErrorCode.notYourChild {
            guard mine == generation else { return }
            status = nil
            phase = .missing
            isOffline = false
        } catch {
            guard mine == generation else { return }
            let message = UserMessage(error)
            if status == nil {
                phase = .failed(message)
            } else if message == .noConnection || message == .timeout {
                isOffline = true
            } else {
                toast = message
            }
        }
    }

    /// Every permission not granted, once; a failure is a toast and the button works again.
    func sendInstructions() async {
        let kinds = kindsToFix
        guard !kinds.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await service.sendInstructions(childId: childId, kinds: kinds)
            wereInstructionsSent = true
        } catch is CancellationError {
            return
        } catch {
            toast = UserMessage(error)
        }
    }
}
