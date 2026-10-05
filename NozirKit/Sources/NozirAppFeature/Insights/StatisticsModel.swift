import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// Which child the Statistics tab shows (spec decision: a switcher above P07,
/// the choice carried on to P08). A child removed in Profile falls back to the
/// first; with no children there is nothing to show.
@MainActor
@Observable
final class StatisticsModel {
    var selectedChildId: UUID?
    let family: FamilyStore
    private(set) var familyFailure: UserMessage?

    init(family: FamilyStore) {
        self.family = family
    }

    /// The tab's own ask for the family, for a cold start that never loaded it
    /// (offline). A failure is kept to be shown; the next call tries again.
    func loadFamily() async {
        guard !family.hasLoaded else { return }
        familyFailure = nil
        do {
            try await family.refresh()
        } catch is CancellationError {
            return
        } catch {
            familyFailure = UserMessage(error)
        }
    }

    var childId: UUID? {
        if let selectedChildId, family.child(selectedChildId) != nil { return selectedChildId }
        return family.children.first?.id
    }

    var showsSwitcher: Bool {
        family.children.count > 1
    }

    func switcherChildren(_ l10n: L10n) -> [NozirSwitcherChild] {
        family.children.enumerated().map { position, child in
            NozirSwitcherChild(
                id: child.id,
                name: child.displayName,
                tone: .forKey(child.avatarKey, position: position),
                accessibilityLabel: l10n.contentDescriptionChildAvatar(child.displayName)
            )
        }
    }
}
