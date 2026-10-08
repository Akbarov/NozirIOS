import SwiftUI
import NozirDesignSystem
import NozirL10n

/// The free-plan lock of a frozen child (P03, P09): the rules stay as they
/// are on the phone; this child can be made the active one for free, or the
/// family can go PRO. With the free way out beside it, the upgrade is a
/// secondary button (Android `PlanLockCard` with a secondary action).
struct FrozenChildCard: View {
    private let isMakingActive: Bool
    private let onMakeActive: () -> Void
    private let onUpgrade: () -> Void
    @Environment(\.l10n) private var l10n

    init(isMakingActive: Bool, onMakeActive: @escaping () -> Void, onUpgrade: @escaping () -> Void) {
        self.isMakingActive = isMakingActive
        self.onMakeActive = onMakeActive
        self.onUpgrade = onUpgrade
    }

    var body: some View {
        NozirCard(tone: .attention) {
            HStack(spacing: NozirSpacing.small) {
                NozirStatusDot(.attention)
                Text(l10n.planLockFrozenBadge).nozirText(.label, color: NozirColor.attentionContent)
            }
            Text(l10n.planLockFrozenChildTitle).nozirText(.titleSmall)
            Text(l10n.planLockFrozenChildBody).nozirText(.bodySmall)
            NozirButton(l10n.planLockChooseActive, variant: .secondary, isLoading: isMakingActive, action: onMakeActive)
            NozirButton(l10n.planLockActionUpgrade, variant: .secondary, action: onUpgrade)
            Text(l10n.planLockSosNote).nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
    }
}
