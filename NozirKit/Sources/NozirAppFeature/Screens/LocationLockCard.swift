import SwiftUI
import NozirDesignSystem
import NozirL10n

/// "Location is on the PRO plan": the plan-lock card of P13 and P14. No upgrade
/// button, and the note says SOS stays free.
struct LocationLockCard: View {
    @Environment(\.l10n) private var l10n

    var body: some View {
        NozirCard {
            Text(l10n.planLockLocationTitle).nozirText(.titleSmall)
            Text(l10n.planLockLocationBody).nozirText(.body)
            Text(l10n.planLockSosNote).nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
    }
}
