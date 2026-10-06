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
    /// A refresh said 404 while a detail is on screen: the alarm ended under it.
    private(set) var isGone = false
    /// Bumped by every load and acknowledge: an older answer never overwrites a newer state.
    private var generation = 0

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

    nonisolated static func dialNumber(configured: String?, fallback: String) -> String {
        LocationTexts.present(configured) ?? fallback
    }

    func load() async {
        generation += 1
        let mine = generation
        do {
            let fetched = try await location.sosAlert(seed.sosId)
            guard mine == generation else { return }
            detail = fetched
            phase = .ready
            isOffline = false
            isGone = false
        } catch is CancellationError {
            return
        } catch let failure as ApiFailure where failure.isNotFound {
            guard mine == generation else { return }
            if detail == nil {
                phase = .missing
            } else {
                isGone = true
            }
        } catch {
            guard mine == generation else { return }
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
            let settled = try await location.acknowledgeSos(seed.sosId)
            generation += 1
            detail = settled
            isOffline = false
        } catch is CancellationError {
            return
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
        detail?.status == .active && !isAcknowledging && !isGone
    }

    /// Apple Maps with the alarm's position as the destination.
    var directionsURL: URL? {
        guard let coordinate = detail?.coordinate else { return nil }
        return URL(string: String(format: "https://maps.apple.com/?daddr=%.6f,%.6f", coordinate.latitude, coordinate.longitude))
    }
}
