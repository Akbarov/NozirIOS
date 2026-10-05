import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// The child details screen (Android `ChildDetailsViewModel`): the P03 form,
/// pre-filled, sending only what changed; removal; the frozen-child lock.
@MainActor
@Observable
public final class ChildDetailsModel {
    public enum Removal: Equatable, Sendable {
        case idle, confirming, removing
    }

    public private(set) var child: Child
    public private(set) var name = ""
    public private(set) var birthYearText = ""
    public private(set) var phoneDigits = ""
    public var avatar: AvatarTone = .teal
    public private(set) var isSaving = false
    public private(set) var wasSaved = false
    public private(set) var message: UserMessage?
    public private(set) var removal: Removal = .idle
    public private(set) var wasRemoved = false
    public private(set) var isFrozen = false
    public private(set) var isMakingActive = false

    private let family: FamilyStore
    private let currentYear: Int

    public init(child: Child, family: FamilyStore, currentYear: Int = Calendar.current.component(.year, from: Date())) {
        self.child = child
        self.family = family
        self.currentYear = currentYear
        load(child)
    }

    private func load(_ child: Child) {
        self.child = child
        name = child.displayName
        birthYearText = String(child.birthYear)
        phoneDigits = UzbekPhone.digits(fromE164: child.phoneE164)
        avatar = AvatarTone.forKey(child.avatarKey)
    }

    public func updateName(_ input: String) {
        name = ChildAge.name(from: input)
        wasSaved = false
    }

    public func updateBirthYear(_ input: String) {
        birthYearText = ChildAge.yearDigits(from: input)
        wasSaved = false
    }

    public func updatePhone(_ input: String) {
        phoneDigits = UzbekPhone.digits(from: input)
        wasSaved = false
    }

    public var age: Int? {
        ChildAge.of(birthYearText: birthYearText, currentYear: currentYear)
    }

    /// The stored year stands even outside the bands; a new one must be inside.
    private var isYearAcceptable: Bool {
        birthYearText == String(child.birthYear) || age != nil
    }

    public var showsPhoneError: Bool {
        !phoneDigits.isEmpty && phoneDigits.count != UzbekPhone.subscriberDigits
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var changes: ChildUpdate {
        var update = ChildUpdate()
        if trimmedName != child.displayName { update.displayName = trimmedName }
        if let year = Int(birthYearText), year != child.birthYear { update.birthYear = year }
        if avatar != AvatarTone.forKey(child.avatarKey) { update.avatarKey = avatar.rawValue }
        if phoneDigits != UzbekPhone.digits(fromE164: child.phoneE164) {
            if phoneDigits.isEmpty {
                update.phone = .cleared
            } else if let number = UzbekPhone.e164(phoneDigits) {
                update.phone = .set(number)
            }
        }
        return update
    }

    public var canSave: Bool {
        !isSaving && !trimmedName.isEmpty && isYearAcceptable && !showsPhoneError && !changes.isEmpty
    }

    public func save() async {
        guard canSave else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            let updated = try await family.service.updateChild(child.id, changes)
            family.replace(updated)
            load(updated)
            wasSaved = true
        } catch {
            message = UserMessage(error)
        }
    }

    public func askToRemove() {
        removal = .confirming
        message = nil
    }

    public func cancelRemove() {
        removal = .idle
    }

    public func confirmRemove() async {
        guard removal == .confirming else { return }
        removal = .removing
        do {
            try await family.service.removeChild(child.id)
            family.remove(child.id)
            wasRemoved = true
        } catch {
            removal = .confirming
            message = UserMessage(error)
        }
    }

    /// An unknown plan freezes nobody (Android `FamilyPlan.Unknown`).
    public func loadPlan() async {
        guard let subscription = try? await family.service.subscription() else { return }
        isFrozen = !subscription.isChildActive(child.id)
    }

    public func makeActive() async {
        guard !isMakingActive else { return }
        isMakingActive = true
        message = nil
        defer { isMakingActive = false }
        do {
            let subscription = try await family.service.chooseActiveChild(child.id)
            isFrozen = !subscription.isChildActive(child.id)
        } catch {
            message = UserMessage(error)
        }
    }
}

func ageGroupName(_ group: AgeGroup, _ l10n: L10n) -> String {
    switch group {
    case .star: l10n.ageGroupStar
    case .explorer: l10n.ageGroupExplorer
    case .independent: l10n.ageGroupIndependent
    }
}
