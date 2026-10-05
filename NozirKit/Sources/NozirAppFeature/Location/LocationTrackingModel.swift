import Foundation
import Observation
import NozirFamily
import NozirNetworking

/// P12b: how often the child's phone reports unasked. Written with the
/// version it was read at; a version that moved meanwhile is re-read and the
/// parent is told — the change is never resent on their behalf.
@MainActor
@Observable
final class LocationTrackingModel {
    enum Notice: Equatable {
        case saved
        /// Changed elsewhere since it was read: the latest is shown.
        case conflict
    }

    let childId: UUID
    let childName: String?
    private(set) var tracking: LocationTracking?
    private(set) var isLoading = false
    private(set) var loadFailure: UserMessage?
    private(set) var message: UserMessage?
    private(set) var notice: Notice?
    private(set) var isSaving = false

    private let family: FamilyStore
    @ObservationIgnored private var saved: LocationTracking?
    @ObservationIgnored private var version: Int64?

    init(childId: UUID, childName: String?, family: FamilyStore) {
        self.childId = childId
        self.childName = childName
        self.family = family
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await family.service.rules(of: childId)
            accept(snapshot)
            loadFailure = nil
        } catch is CancellationError {
            return
        } catch {
            loadFailure = UserMessage(error)
        }
    }

    func setEnabled(_ enabled: Bool) {
        edit { $0.isEnabled = enabled }
    }

    func setInterval(_ minutes: Int) {
        edit { $0.intervalMinutes = minutes }
    }

    func setZoneInterval(_ minutes: Int) {
        edit { $0.zoneIntervalMinutes = minutes }
    }

    func setMove(_ metres: Int) {
        edit { $0.moveMetres = metres }
    }

    var canSave: Bool {
        guard !isSaving, let tracking, version != nil else { return false }
        return tracking != saved
    }

    func save() async {
        guard canSave, let tracking, let version else { return }
        isSaving = true
        message = nil
        notice = nil
        defer { isSaving = false }
        do {
            let snapshot = try await family.service.setLocationTracking(tracking, of: childId, version: version)
            accept(snapshot)
            notice = .saved
        } catch is CancellationError {
            return
        } catch {
            let failure = UserMessage(error)
            if failure == .conflict, let fresh = try? await family.service.rules(of: childId) {
                accept(fresh)
                notice = .conflict
            } else {
                message = failure
            }
        }
    }

    private func edit(_ change: (inout LocationTracking) -> Void) {
        guard var copy = tracking else { return }
        change(&copy)
        tracking = copy
        notice = nil
        message = nil
    }

    private func accept(_ snapshot: RuleSnapshot) {
        version = snapshot.version
        saved = snapshot.locationTracking
        tracking = snapshot.locationTracking
    }
}
