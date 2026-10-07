import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// One waiting ask on Home (Android `ExtraTimeRequestRow`). The accent is in
/// the tile and the sub-line, not a status colour: something to answer, not
/// something to worry about (plan deviation T2).
struct TimeRequestRow: View {
    let request: ExtraTimeRequest
    let action: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        Button(action: action) {
            NozirCard {
                HStack(spacing: NozirSpacing.compact) {
                    Text(l10n.glyphChat)
                        .font(.system(size: 18))
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: NozirRadius.cardCompact).fill(NozirColor.primaryContainer))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TimeRequestTexts.rowTitle(request, l10n)).nozirText(.body)
                        Text(TimeRequestTexts.rowBody(request, l10n))
                            .nozirText(.bodySmall, color: NozirColor.primaryAccent)
                    }
                    Spacer(minLength: 0)
                    Text(l10n.glyphChevron)
                        .nozirText(.titleSmall, color: NozirColor.primaryAccent)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
