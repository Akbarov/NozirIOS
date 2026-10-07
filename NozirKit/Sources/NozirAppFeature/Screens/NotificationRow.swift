import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// One line of the record (Android `NotificationRow`): the tier's dot, what
/// happened (bold while unread — the only unread mark, plan deviation N3),
/// "bola · vaqt", and "Ilova ichida qoldi" for a tier that never rang the
/// phone. One button for VoiceOver; the dot is decoration. Nothing is cut at
/// large text sizes.
struct NotificationRow: View {
    let notification: ParentNotification
    /// The moment the list draws, for "Bugun" / "Kecha".
    let now: Date
    let action: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        Button(action: action) {
            NozirCard(tone: NotificationTexts.cardTone(notification.tier)) {
                HStack(alignment: .top, spacing: NozirSpacing.small) {
                    NozirStatusDot(NotificationTexts.dotLevel(notification.tier))
                        .padding(.top, NozirSpacing.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NotificationTexts.headline(notification, l10n))
                            .bold(!notification.isRead)
                            .nozirText(.body)
                        Text(NotificationTexts.caption(notification, now: now, l10n))
                            .nozirText(.bodySmall, color: NozirColor.textTertiary)
                        if let note = NotificationTexts.inAppNote(notification.tier, l10n) {
                            Text(note).nozirText(.bodySmall, color: NozirColor.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
