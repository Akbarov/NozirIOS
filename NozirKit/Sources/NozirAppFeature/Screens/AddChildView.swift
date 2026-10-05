import SwiftUI
import NozirDesignSystem
import NozirL10n

/// P03 as Android `AddChildScreen`: name, birth year (and the age it means),
/// an optional phone, a colour.
struct AddChildView: View {
    @State private var model: AddChildModel
    private let onContinue: (ChildDraft) -> Void
    @Environment(\.l10n) private var l10n

    init(model: AddChildModel, onContinue: @escaping (ChildDraft) -> Void) {
        _model = State(initialValue: model)
        self.onContinue = onContinue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                Text(l10n.addChildTopBar).nozirText(.titleLarge)
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
                        Text(l10n.addChildAgeYears(age)).nozirText(.titleSmall)
                        Text(l10n.addChildAgeNote).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: NozirSpacing.small) {
                    NozirPhoneField(
                        l10n.addChildLabelPhone,
                        digits: Binding(get: { model.phoneDigits }, set: { model.updatePhone($0) }),
                        prefix: l10n.phoneFieldPrefix,
                        placeholder: l10n.phoneFieldPlaceholder,
                        error: model.showsPhoneError ? l10n.addChildErrorPhone : nil
                    )
                    Text(l10n.addChildPhoneNote).nozirText(.bodySmall, color: NozirColor.textTertiary)
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
                NozirButton(l10n.buttonContinue, size: .callToAction) {
                    if let draft = model.draft { onContinue(draft) }
                }
                .disabled(!model.canContinue)
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenAddChildTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
