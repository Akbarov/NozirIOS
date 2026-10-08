import SwiftUI
import NozirDesignSystem
import NozirL10n

/// "Location is on the PRO plan" (Android `PlanLockCard`, tone INFO): the
/// plan-lock card of P13, P14 and P12b. The note says SOS stays free; the
/// button opens P19.
struct LocationLockCard: View {
    private let onUpgrade: () -> Void
    @Environment(\.l10n) private var l10n

    init(onUpgrade: @escaping () -> Void) {
        self.onUpgrade = onUpgrade
    }

    var body: some View {
        NozirCard(tone: .info) {
            Text(l10n.planLockLocationTitle).nozirText(.titleSmall)
            Text(l10n.planLockLocationBody).nozirText(.body)
            Text(l10n.planLockSosNote).nozirText(.bodySmall, color: NozirColor.textSecondary)
            NozirButton(l10n.planLockActionUpgrade, action: onUpgrade)
        }
    }
}
