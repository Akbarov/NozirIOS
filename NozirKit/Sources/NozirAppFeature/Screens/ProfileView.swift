import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P21 as Android `ProfileScreen`, with only the rows whose screens exist.
struct ProfileView: View {
    @State private var model: ProfileModel
    private let onAddChild: () -> Void
    private let onOpenChild: (Child) -> Void
    private let onPair: (Child) -> Void
    private let onOpenRules: () -> Void
    private let onOpenNotifications: () -> Void
    private let onOpenPrivacy: () -> Void
    @Environment(\.l10n) private var l10n
    @State private var showsTheme = false
    @State private var showsLanguage = false

    init(
        model: ProfileModel,
        onAddChild: @escaping () -> Void,
        onOpenChild: @escaping (Child) -> Void,
        onPair: @escaping (Child) -> Void,
        onOpenRules: @escaping () -> Void,
        onOpenNotifications: @escaping () -> Void,
        onOpenPrivacy: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onAddChild = onAddChild
        self.onOpenChild = onOpenChild
        self.onPair = onPair
        self.onOpenRules = onOpenRules
        self.onOpenNotifications = onOpenNotifications
        self.onOpenPrivacy = onOpenPrivacy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                parentCard
                if let message = model.message {
                    NozirInlineMessage(message.text(l10n))
                }
                NozirSectionTitle(l10n.profileSectionChildren)
                NozirCard {
                    ForEach(Array(model.family.children.enumerated()), id: \.element.id) { position, child in
                        childRow(child, position: position)
                        Divider()
                    }
                    Button(action: onAddChild) {
                        Text(l10n.profileAddChild)
                            .nozirText(.titleSmall, color: NozirColor.primaryAccent)
                            .frame(maxWidth: .infinity, minHeight: NozirSize.control, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if model.showsRules {
                    NozirCard {
                        NozirSettingsRow(l10n.profileRowRules, action: onOpenRules)
                    }
                }
                NozirSectionTitle(l10n.profileSectionSettings)
                NozirCard {
                    NozirSettingsRow(l10n.profileRowNotifications, action: onOpenNotifications)
                    Divider()
                    NozirSettingsRow(l10n.profileRowPrivacy, action: onOpenPrivacy)
                    Divider()
                    NozirSettingsRow(l10n.profileRowTheme, value: themeLabel(model.appearance.mode)) { showsTheme = true }
                    Divider()
                    NozirSettingsRow(l10n.profileRowLanguage, value: languageLabel(model.language.current)) { showsLanguage = true }
                }
                NozirButton(l10n.profileActionSignOut, variant: .criticalOutline, isLoading: model.isSigningOut) {
                    Task { await model.signOut() }
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenProfileTitle)
        .task { await model.load() }
        .refreshable { await model.load() }
        .confirmationDialog(l10n.themeSheetTitle, isPresented: $showsTheme, titleVisibility: .visible) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                Button(themeLabel(mode)) { model.choose(mode) }
            }
        }
        .confirmationDialog(l10n.languageSheetTitle, isPresented: $showsLanguage, titleVisibility: .visible) {
            ForEach(AppLanguage.allCases, id: \.self) { language in
                Button(languageLabel(language)) {
                    Task { await model.choose(language) }
                }
            }
        }
    }

    private var parentCard: some View {
        NozirCard {
            HStack(spacing: NozirSpacing.compact) {
                NozirAvatar(name: model.displayName(l10n), tone: .teal, fallbackInitial: l10n.previewAvatarInitial, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName(l10n)).nozirText(.titleSmall)
                    if let phone = model.phone {
                        Text(phone).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                }
            }
        }
    }

    private func childRow(_ child: Child, position: Int) -> some View {
        let status = ProfileModel.status(of: child.pairingState, l10n)
        return HStack(spacing: NozirSpacing.compact) {
            Button {
                onOpenChild(child)
            } label: {
                HStack(spacing: NozirSpacing.compact) {
                    NozirAvatar(
                        name: child.displayName,
                        tone: .forKey(child.avatarKey, position: position),
                        fallbackInitial: l10n.previewAvatarInitial
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.profileChildNameAndAge(child.displayName, model.age(of: child))).nozirText(.body)
                        HStack(spacing: NozirSpacing.extraSmall) {
                            NozirStatusDot(status.level)
                            Text(status.label).nozirText(.bodySmall, color: NozirColor.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(l10n.contentDescriptionChildDetails)
            Button(child.pairingState == .paired ? l10n.profileActionRepair : l10n.profileActionPair) {
                onPair(child)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NozirColor.primaryAccent)
        }
        .padding(.vertical, NozirSpacing.extraSmall)
    }

    private func themeLabel(_ mode: AppearanceMode) -> String {
        switch mode {
        case .light: l10n.profileThemeLight
        case .dark: l10n.profileThemeDark
        case .system: l10n.profileThemeSystem
        }
    }

    private func languageLabel(_ language: AppLanguage) -> String {
        switch language {
        case .uz: l10n.languageUz
        case .ru: l10n.languageRu
        case .en: l10n.languageEn
        }
    }
}
