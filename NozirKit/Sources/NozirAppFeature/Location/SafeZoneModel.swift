import Foundation
import Observation
import NozirLocation
import NozirNetworking

/// P14: one screen for a new zone and an existing one. The centre is placed by
/// tapping the map (no search: that needs a places service). A new zone opens
/// on the child's last fix and says the pin was placed for the parent.
@MainActor
@Observable
final class SafeZoneModel {
    enum Hint: Equatable {
        case needsPlace, needsName, centredOnLastFix
    }

    enum Deletion: Equatable {
        case idle, confirming, deleting
    }

    static let radiusRange = 50...5000
    static let defaultRadius = 200
    static let nameLimit = 60

    let childId: UUID
    let zoneId: UUID?
    private(set) var name = ""
    private(set) var radius = SafeZoneModel.defaultRadius
    var notifyOnEnter = true
    var notifyOnExit = false
    private(set) var centre: Coordinate?
    private(set) var isLoading = true
    /// The zone was deleted on another phone: say so rather than open a blank form.
    private(set) var isMissing = false
    /// Editing, and the stored zone could not be read: no form, so nothing blank can be saved over it.
    private(set) var loadFailed = false
    private(set) var message: UserMessage?
    private(set) var isSaving = false
    private(set) var wasSaved = false
    private(set) var deletion: Deletion = .idle
    private(set) var wasDeleted = false

    private let location: any LocationService
    @ObservationIgnored private var stored: SafeZoneDraft?
    @ObservationIgnored private var centredOnFix = false
    @ObservationIgnored private var started = false

    init(childId: UUID, zoneId: UUID?, location: any LocationService) {
        self.childId = childId
        self.zoneId = zoneId
        self.location = location
    }

    var isEditing: Bool {
        zoneId != nil
    }

    /// Runs once: a repeated `.task` must not overwrite edits in progress.
    /// Only a failed load may be run again (the retry button).
    func load() async {
        guard !started || loadFailed else { return }
        started = true
        loadFailed = false
        isLoading = true
        defer { isLoading = false }
        message = nil
        if let zoneId {
            do {
                let zones = try await location.safeZones(of: childId)
                guard let zone = zones.first(where: { $0.id == zoneId }) else {
                    isMissing = true
                    message = .notFound
                    return
                }
                stored = zone.draft
                name = zone.name
                radius = zone.radiusMeters
                notifyOnEnter = zone.notifyOnEnter
                notifyOnExit = zone.notifyOnExit
                centre = zone.coordinate
            } catch is CancellationError {
                started = false
                return
            } catch {
                loadFailed = true
                message = UserMessage(error)
            }
        } else if centre == nil, let fix = try? await location.location(of: childId).coordinate {
            centre = fix
            centredOnFix = true
        }
    }

    func updateName(_ text: String) {
        name = String(text.prefix(Self.nameLimit))
    }

    func updateRadius(_ metres: Int) {
        radius = min(max(metres, Self.radiusRange.lowerBound), Self.radiusRange.upperBound)
    }

    func place(at coordinate: Coordinate) {
        centre = coordinate
        centredOnFix = false
    }

    /// What would be sent; nil until there is a place and a name.
    var draft: SafeZoneDraft? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let centre, !trimmed.isEmpty, !isMissing, !loadFailed, !(isEditing && stored == nil) else { return nil }
        return SafeZoneDraft(
            name: trimmed,
            latitude: centre.latitude,
            longitude: centre.longitude,
            radiusMeters: radius,
            notifyOnEnter: notifyOnEnter,
            notifyOnExit: notifyOnExit,
            iconKey: stored?.iconKey
        )
    }

    var canSave: Bool {
        guard !isSaving, deletion == .idle, let draft else { return false }
        return draft != stored
    }

    var hint: Hint? {
        if centre == nil { return .needsPlace }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .needsName }
        if centredOnFix { return .centredOnLastFix }
        return nil
    }

    func save() async {
        guard canSave, let draft else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            if let zoneId {
                _ = try await location.updateSafeZone(zoneId, draft)
            } else {
                _ = try await location.createSafeZone(draft, for: childId)
            }
            wasSaved = true
        } catch is CancellationError {
            return
        } catch {
            message = UserMessage(error)
        }
    }

    func askToDelete() {
        guard isEditing, !isMissing, !loadFailed, !isSaving, deletion == .idle else { return }
        deletion = .confirming
    }

    func cancelDelete() {
        guard deletion == .confirming else { return }
        deletion = .idle
    }

    func confirmDelete() async {
        guard deletion == .confirming, !isSaving, let zoneId else { return }
        deletion = .deleting
        message = nil
        do {
            try await location.deleteSafeZone(zoneId)
            wasDeleted = true
        } catch is CancellationError {
            deletion = .confirming
        } catch let failure as ApiFailure where failure.isNotFound {
            wasDeleted = true
        } catch {
            deletion = .confirming
            message = UserMessage(error)
        }
    }
}
