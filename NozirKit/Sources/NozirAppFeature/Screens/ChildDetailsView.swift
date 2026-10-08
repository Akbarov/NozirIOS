import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// Android `ChildDetailsScreen`: edit, the frozen lock, remove; the rules and
/// protection rows open P09 and P18 for this child.
struct ChildDetailsView: View {
    @State private var model: ChildDetailsModel
    private let onRemoved: () -> Void
    private let onOpenRules: () -> Void
    private let onOpenProtection: () -> Void
    @Environment(\.l10n) private var l10n

    init(
        model: ChildDetailsModel,
        onRemoved: @escaping () -> Void,
        onOpenRules: @escaping () -> Void,
        onOpenProtection: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onRemoved = onRemoved
        self.onOpenRules = onOpenRules
        self.onOpenProtection = onOpenProtection
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                HStack(spacing: NozirSpacing.compact) {
                    NozirAvatar(name: model.name, tone: model.avatar, fallbackInitial: l10n.previewAvatarInitial, size: 56)
                    Text(model.child.displayName).nozirText(.titleLarge)
                }
                if model.isFrozen {
                    FrozenChildCard(isMakingActive: model.isMakingActive) {
                        Task { await model.makeActive() }
                    }
                }
                form
                NozirCard {
                    NozirSettingsRow(l10n.profileRowRules, action: onOpenRules)
                    Divider()
                    NozirSettingsRow(l10n.screenProtectionTitle, action: onOpenProtection)
                }
                if let message = model.message {
                    NozirInlineMessage(message.text(l10n))
                }
                if model.wasSaved {
                    Text(l10n.childDetailsSaved).nozirText(.bodySmall, color: NozirColor.goodContent)
                }
                NozirButton(l10n.childDetailsActionSave, size: .callToAction, isLoading: model.isSaving) {
                    Task { await model.save() }
                }
                .disabled(!model.canSave && !model.isSaving)
                removal
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.childDetailsTopBar)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadPlan() }
        .onChange(of: model.wasRemoved) { _, removed in
            if removed { onRemoved() }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.large) {
            NozirTextField(
                l10n.addChildLabelName,
                text: Binding(get: { model.name }, set: { model.updateName($0) }),
                placeholder: l10n.addChildNamePlaceholder
            )
            NozirTextField(
                l10n.addChildLabelBirthYear,
                text: Binding(get: { model.birthYearText }, set: { model.updateBirthYear($0) }),
                placeholder: l10n.addChildBirthYearPlaceholder,
                keyboard: .numberPad
            )
            if let age = model.age {
                NozirCard {
                    // The server's band is shown only for the stored year: a year
                    // being edited has no band until it is saved.
                    if model.birthYearText == String(model.child.birthYear), let group = model.child.ageGroup {
                        Text(l10n.addChildAgeMode(age, ageGroupName(group, l10n))).nozirText(.titleSmall)
                    } else {
                        Text(l10n.addChildAgeYears(age)).nozirText(.titleSmall)
                    }
                    Text(l10n.addChildAgeNote).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: NozirSpacing.small) {
                NozirPhoneField(
                    l10n.childDetailsLabelPhone,
                    digits: Binding(get: { model.phoneDigits }, set: { model.updatePhone($0) }),
                    prefix: l10n.phoneFieldPrefix,
                    placeholder: l10n.phoneFieldPlaceholder,
                    error: model.showsPhoneError ? l10n.childDetailsErrorPhone : nil
                )
                Text(l10n.childDetailsPhoneNote).nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
            VStack(alignment: .leading, spacing: NozirSpacing.small) {
                Text(l10n.addChildLabelAvatar).nozirText(.bodySmall, color: NozirColor.textSecondary)
                NozirAvatarPicker(
                    selection: $model.avatar,
                    name: model.name,
                    fallbackInitial: l10n.previewAvatarInitial,
                    accessibilityLabel: l10n.contentDescriptionAvatarChoice
                )
            }
        }
    }

    @ViewBuilder
    private var removal: some View {
        switch model.removal {
        case .idle:
            NozirButton(l10n.childDetailsActionRemove, variant: .criticalOutline) { model.askToRemove() }
        case .confirming, .removing:
            NozirCard(tone: .attention) {
                Text(l10n.childDetailsRemoveTitle(model.child.displayName)).nozirText(.titleSmall)
                Text(l10n.childDetailsRemoveBody).nozirText(.bodySmall)
                HStack(spacing: NozirSpacing.small) {
                    NozirButton(l10n.childDetailsRemoveCancel, variant: .secondary) { model.cancelRemove() }
                        .disabled(model.removal == .removing)
                    NozirButton(l10n.childDetailsRemoveConfirm, variant: .criticalOutline, isLoading: model.removal == .removing) {
                        Task { await model.confirmRemove() }
                    }
                }
            }
        }
    }
}
