import Foundation
import Observation
import NozirFamily
import NozirNetworking

/// P12b: how often the child's phone reports unasked. Written with the
/// version it was read at; a version that moved meanwhile is re-read and the
/// parent is told — the change is never resent on their behalf.
///
/// Opened from the rules hub it works on the hub's session: the rule is read
/// from it, written against its version, and the answer goes back to it.
/// From the Location tab (no session) it reads and writes on its own.
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
    private let session: ChildRulesSession?
    @ObservationIgnored private var saved: LocationTracking?
    @ObservationIgnored private var version: Int64?

    init(childId: UUID, childName: String?, family: FamilyStore, session: ChildRulesSession? = nil) {
        self.childId = childId
        self.childName = childName
        self.family = family
        self.session = session
    }

    /// A repeated `.task` (a tab switch) must not overwrite edits in progress:
    /// only a load that has not produced a rule yet may run again (the retry).
    func load() async {
        guard tracking == nil else { return }
        isLoading = true
        defer { isLoading = false }
        if let session {
            await session.load()
            if let snapshot = session.snapshot {
                accept(snapshot)
                loadFailure = nil
            } else {
                loadFailure = session.loadFailure
            }
            return
        }
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
        guard !isSaving, !(session?.isFrozen ?? false), let tracking, version != nil else { return false }
        return tracking != saved
    }

    func save() async {
        guard canSave, let tracking, let version else { return }
        isSaving = true
        message = nil
        notice = nil
        defer { isSaving = false }
        if let session {
            await save(tracking, through: session)
            return
        }
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

    /// The session's version, which another screen of the hub may have moved.
    /// A tracking rule changed under the edit is shown, not written over.
    private func save(_ tracking: LocationTracking, through session: ChildRulesSession) async {
        guard let held = session.snapshot else { return }
        guard held.locationTracking == saved else {
            accept(held)
            notice = .conflict
            return
        }
        let service = family.service
        let childId = self.childId
        let version = held.version
        let outcome = await session.write { try await service.setLocationTracking(tracking, of: childId, version: version) }
        switch outcome {
        case .saved:
            if let snapshot = session.snapshot { accept(snapshot) }
            notice = .saved
        case .conflict:
            if let snapshot = session.snapshot { accept(snapshot) }
            notice = .conflict
        case .failed(let failure):
            message = failure
        case .cancelled:
            break
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
