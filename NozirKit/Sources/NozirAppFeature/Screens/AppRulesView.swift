import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P11 (Android `AppRulesContent`): the app rules, the never-blocked promise,
/// and "Ilova qo'shish" opening the phone's apps, with a search, on this page.
/// A row opens that app's editor on a screen of its own (spec D1).
struct AppRulesView: View {
    @State private var model: AppRulesModel
    private let onOpen: (AppRuleTarget) -> Void
    @Environment(\.l10n) private var l10n

    init(model: AppRulesModel, onOpen: @escaping (AppRuleTarget) -> Void) {
        _model = State(initialValue: model)
        self.onOpen = onOpen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.appRulesTitle).nozirText(.titleLarge)
                    Text(l10n.appRulesSubtitle).nozirText(.bodySmall, color: NozirColor.textTertiary)
                }
                if model.session.snapshot != nil {
                    if model.session.isOffline {
                        NozirOfflineNotice(l10n.stateOfflineNotice)
                    }
                    rules
                    NozirCard(tone: .attention) {
                        Text(l10n.appRulesNeverBlocked).nozirText(.bodySmall)
                    }
                    NozirButton(l10n.appRulesAdd, variant: .ghost) { model.toggleChoosing() }
                        .disabled(model.session.isFrozen || model.hasNothingToAdd)
                    if model.isChoosingApp {
                        picker
                    }
                } else if let failure = model.session.loadFailure {
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
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenAppRulesTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Once: a tab switch finds the session, the apps and the search as they were.
        .task { await model.load() }
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private var rules: some View {
        if model.policies.isEmpty {
            NozirEmptyState(title: l10n.appRulesEmptyTitle, message: l10n.appRulesEmptyBody)
        } else {
            NozirCard {
                ForEach(Array(model.policies.enumerated()), id: \.element.packageId) { index, policy in
                    if index > 0 { Divider() }
                    policyRow(policy)
                }
            }
        }
    }

    /// Name, the rule in one line (accented when it closes the app), and `›`.
    private func policyRow(_ policy: AppPolicy) -> some View {
        let name = model.name(of: policy)
        let summary = AppRuleTexts.summary(policy, l10n)
        return Button {
            onOpen(model.open(policy))
        } label: {
            HStack(spacing: NozirSpacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).nozirText(.body)
                    if let summary {
                        Text(summary).nozirText(
                            .bodySmall,
                            color: AppRuleTexts.closesTheApp(policy) ? NozirColor.actionContent : NozirColor.textTertiary
                        )
                    }
                }
                Spacer(minLength: NozirSpacing.small)
                Text(l10n.glyphChevron)
                    .nozirText(.body, color: NozirColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: NozirSize.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.appRulesEdit(name))
        .accessibilityValue(summary ?? "")
        .accessibilityAddTraits(.isButton)
    }

    /// The phone's apps a rule could be written for. A failed read says so
    /// with Retry (spec D3); nothing left to add is not a search. While the
    /// policy list above already shows the empty title and body (ruling F5),
    /// the picker does not repeat them.
    @ViewBuilder
    private var picker: some View {
        if let failure = model.appsLoadFailure, model.installedApps == nil {
            NozirInlineMessage(failure.text(l10n))
            NozirButton(l10n.stateActionRetry, variant: .secondary) {
                Task { await model.retryApps() }
            }
        } else if model.installedApps == nil {
            ProgressView().frame(maxWidth: .infinity)
        } else if model.addableApps.isEmpty {
            if !model.policies.isEmpty {
                NozirEmptyState(title: l10n.appRulesEmptyTitle, message: l10n.appRulesEmptyBody)
            }
        } else {
            searchField
            if model.shownApps.isEmpty {
                Text(l10n.appRulesSearchNoMatch(model.query.trimmingCharacters(in: .whitespacesAndNewlines)))
                    .nozirText(.bodySmall, color: NozirColor.textSecondary)
            } else {
                NozirCard {
                    ForEach(Array(model.shownApps.enumerated()), id: \.element.packageId) { index, app in
                        if index > 0 { Divider() }
                        appRow(app)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: NozirSpacing.small) {
            Text(l10n.glyphSearch)
                .nozirText(.bodySmall, color: NozirColor.textTertiary)
                .accessibilityHidden(true)
            TextField(
                "",
                text: Binding(get: { model.query }, set: { model.setQuery($0) }),
                prompt: Text(l10n.appRulesSearchPlaceholder).foregroundColor(NozirColor.textTertiary)
            )
            .nozirText(.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel(l10n.appRulesSearchPlaceholder)
        }
        .padding(.horizontal, NozirSpacing.medium)
        .frame(minHeight: NozirSize.control)
        .background(RoundedRectangle(cornerRadius: NozirRadius.field).fill(NozirColor.card))
        .overlay(
            RoundedRectangle(cornerRadius: NozirRadius.field)
                .strokeBorder(NozirColor.border, lineWidth: NozirSize.borderResting)
        )
    }

    private func appRow(_ app: InstalledApp) -> some View {
        let name = AppRuleTexts.name(app)
        return Button {
            if let target = model.choose(app) {
                onOpen(target)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).nozirText(.body)
                Text(l10n.appRulesAddLabel).nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: NozirSize.control, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.appRulesEdit(name))
        .accessibilityValue(l10n.appRulesAddLabel)
        .accessibilityAddTraits(.isButton)
    }
}
