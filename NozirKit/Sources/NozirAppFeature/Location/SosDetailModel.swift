import Foundation
import Observation
import NozirFamily
import NozirInsights
import NozirLocation
import NozirNetworking

/// P15. Paints at once from the banner's copy (who, when), then fills in from
/// the server. No plan, rate or preference check anywhere on this screen.
/// "I have seen it" settles the alarm once: a second tap while the first is in
/// flight does nothing.
@MainActor
@Observable
final class SosDetailModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// 404: cancelled or expired. An answer, not a fault.
        case missing
        case failed(UserMessage)
    }

    let seed: ActiveSos
    private(set) var detail: SosAlertDetail?
    private(set) var phase: Phase = .loading
    private(set) var isOffline = false
    private(set) var isAcknowledging = false
    private(set) var acknowledgeFailed = false

    private let child: Child?
    private let emergencyNumber: String
    private let location: any LocationService

    /// `emergencyNumber` is the config's, or the compiled-in "112": the dial
    /// button must work with no network and no session.
    init(seed: ActiveSos, child: Child?, emergencyNumber: String, location: any LocationService) {
        self.seed = seed
        self.child = child
        self.emergencyNumber = emergencyNumber
        self.location = location
    }

    func load() async {
        do {
            detail = try await location.sosAlert(seed.sosId)
            phase = .ready
            isOffline = false
        } catch is CancellationError {
            return
        } catch let failure as ApiFailure where failure.isNotFound {
            phase = detail == nil ? .missing : phase
        } catch {
            if detail == nil {
                phase = .failed(UserMessage(error))
            } else {
                isOffline = true
            }
        }
    }

    func acknowledge() async {
        guard canAcknowledge else { return }
        isAcknowledging = true
        acknowledgeFailed = false
        defer { isAcknowledging = false }
        do {
            detail = try await location.acknowledgeSos(seed.sosId)
        } catch {
            acknowledgeFailed = true
        }
    }

    var childName: String? {
        LocationTexts.present(detail?.childName) ?? LocationTexts.present(seed.childName) ?? LocationTexts.present(child?.displayName)
    }

    var triggeredAt: Date {
        detail?.triggeredAt ?? seed.triggeredAt
    }

    /// Who and what to dial, through the banner's own rules.
    var call: SosAlert {
        let named = ActiveSos(sosId: seed.sosId, childId: seed.childId, childName: childName, triggeredAt: triggeredAt)
        return SosAlert(named, child: child, emergencyNumber: emergencyNumber, phone: detail?.childPhoneE164)
    }

    var canAcknowledge: Bool {
        detail?.status == .active && !isAcknowledging
    }

    /// Apple Maps with the alarm's position as the destination.
    var directionsURL: URL? {
        guard let coordinate = detail?.coordinate else { return nil }
        return URL(string: "https://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)")
    }
}
