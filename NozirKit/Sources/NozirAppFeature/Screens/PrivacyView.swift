import SwiftUI
import NozirDesignSystem
import NozirL10n
import NozirPrivacy

/// P20 as Android `PrivacyContent`: who else reads this list, what the parent
/// sees and does not see (the server's words only), the promise, the policy
/// link, and the deletion section pinned below the scroll. The button, the
/// confirmation and the receipt take the same place, one at a time.
struct PrivacyView: View {
    @State private var model: PrivacyModel
    @Environment(\.l10n) private var l10n
    @Environment(\.openURL) private var openURL
    @AccessibilityFocusState private var confirmationFocused: Bool

    init(model: PrivacyModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.compact) {
                if model.isOffline {
                    NozirOfflineNotice(l10n.stateOfflineNotice)
                }
                Text(model.caption(l10n))
                    .nozirText(.bodySmall, color: NozirColor.textTertiary)
                disclosureContent
                if let policy = model.config.policyURL {
                    NozirCard {
                        NozirSettingsRow(l10n.privacyPolicyRow) { openURL(policy) }
                            .accessibilityAddTraits(.isLink)
                    }
                }
            }
            .padding(NozirSpacing.medium)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            deletionSection
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenPrivacyTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        // VoiceOver lands on the question, not on the button that is gone.
        .onChange(of: model.deletion) { _, stage in
            if stage == .confirming {
                confirmationFocused = true
            }
        }
        .nozirToast(Binding(
            get: { model.toast?.text(l10n) },
            set: { if $0 == nil { model.toast = nil } }
        ))
    }

    @ViewBuilder
    private var disclosureContent: some View {
        if let disclosure = model.disclosure {
            if disclosure.isEmpty {
                NozirEmptyState(title: l10n.privacyDisclosureEmptyTitle, message: l10n.privacyDisclosureEmptyBody)
            } else {
                if !disclosure.seen.isEmpty {
                    disclosureCard(seen: true, items: disclosure.seen)
                }
                if !disclosure.notSeen.isEmpty {
                    disclosureCard(seen: false, items: disclosure.notSeen)
                }
                Text(l10n.privacyPromise)
                    .nozirText(.bodySmall, color: NozirColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if !disclosure.documentVersion.isEmpty {
                    Text(l10n.privacyDocumentVersion(disclosure.documentVersion))
                        .nozirText(.bodySmall, color: NozirColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        } else if let failure = model.loadFailure {
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: failure.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    /// One half of the promise. The tick or the cross and the label carry the
    /// meaning; the colour only agrees with them.
    private func disclosureCard(seen: Bool, items: [DisclosureItem]) -> some View {
        let accent = seen ? NozirColor.primaryAccent : NozirColor.criticalContent
        return NozirCard(tone: seen ? .plain : .critical) {
            HStack(spacing: NozirSpacing.small) {
                Text(seen ? l10n.glyphCheck : l10n.glyphCross)
                    .nozirText(.label, color: seen ? NozirColor.onPrimary : NozirColor.card)
                    .frame(width: NozirSize.icon, height: NozirSize.icon)
                    .background(Circle().fill(seen ? NozirColor.primary : NozirColor.criticalContent))
                Text(seen ? l10n.privacySeenLabel : l10n.privacyNotSeenLabel)
                    .nozirText(.titleSmall, color: accent)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(seen ? l10n.contentDescriptionPrivacySeen : l10n.contentDescriptionPrivacyNotSeen)
            .accessibilityAddTraits(.isHeader)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: NozirSpacing.small) {
                    Text(l10n.glyphBullet)
                        .nozirText(.body, color: accent)
                        .accessibilityHidden(true)
                    Text(item.text).nozirText(.body)
                }
            }
        }
    }

    @ViewBuilder
    private var deletionSection: some View {
        switch model.deletion {
        case .unknown:
            EmptyView()
        case .idle:
            if model.canRequestDeletion {
                pinned {
                    NozirButton(l10n.privacyActionDelete, variant: .secondary) { model.startDelete() }
                }
            }
        case .confirming, .submitting:
            pinned { confirmationCard(isSubmitting: model.deletion == .submitting) }
        case .requested(let executableAt):
            pinned {
                NozirCard(tone: .attention) {
                    Text(l10n.privacyDeleteRequestedTitle).nozirText(.titleSmall)
                    Text(model.requestedBody(executableAt, l10n))
                        .nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func pinned<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, NozirSpacing.medium)
            .padding(.vertical, NozirSpacing.compact)
            .frame(maxWidth: .infinity)
            .background(NozirColor.background)
    }

    /// A card where the button was, not an alert: full sentences about what
    /// goes and when, and the refusal first.
    private func confirmationCard(isSubmitting: Bool) -> some View {
        NozirCard(tone: .critical) {
            Text(l10n.privacyDeleteTitle)
                .nozirText(.titleSmall)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($confirmationFocused)
            Text(model.deleteBody(l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            // Side by side when both fit; stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NozirSpacing.small) { confirmationButtons(isSubmitting: isSubmitting) }
                VStack(spacing: NozirSpacing.small) { confirmationButtons(isSubmitting: isSubmitting) }
            }
        }
    }

    @ViewBuilder
    private func confirmationButtons(isSubmitting: Bool) -> some View {
        NozirButton(l10n.privacyDeleteCancel, variant: .secondary) { model.cancelDelete() }
            .disabled(isSubmitting)
        NozirButton(l10n.privacyDeleteConfirm, variant: .criticalOutline, isLoading: isSubmitting) {
            Task { await model.confirmDelete() }
        }
    }
}
