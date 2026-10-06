import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// One app's rule (Android `AppRuleEditor`): the mode, then what the mode
/// needs — the daily time, or the hours and the days — and "Saqlash".
struct AppRuleView: View {
    @State private var model: AppRuleModel
    @Environment(\.l10n) private var l10n

    init(model: AppRuleModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                if let policy = model.policy {
                    if model.session.isOffline {
                        NozirOfflineNotice(l10n.stateOfflineNotice)
                    }
                    NozirCard {
                        modePicker
                        if policy.mode == .dailyLimit {
                            RuleMinuteSlider(
                                title: l10n.appRuleDailyLimitSlider,
                                value: Binding(
                                    get: { policy.dailyLimitMinutes ?? AppRuleModel.defaultDailyLimitMinutes },
                                    set: { model.setDailyLimitMinutes($0) }
                                ),
                                range: RuleMinuteRange.appDailyLimit,
                                accessibilityLabel: l10n.appRuleDailyLimitSlider
                            )
                        }
                        if let window = model.window {
                            HStack(spacing: NozirSpacing.medium) {
                                RuleTimePicker(l10n.appRuleWindowStart, time: Binding(get: { window.start }, set: { model.setWindowStart($0) }))
                                RuleTimePicker(l10n.appRuleWindowEnd, time: Binding(get: { window.end }, set: { model.setWindowEnd($0) }))
                            }
                        }
                    }
                    .disabled(model.session.isFrozen)
                    if let window = model.window {
                        NozirCard {
                            RuleDaysSection(title: l10n.appRuleWindowDays, describesNights: false, activeDays: Set(window.days)) {
                                model.toggleDay($0)
                            }
                        }
                        .disabled(model.session.isFrozen)
                    }
                    RuleSaveFooter(
                        notice: model.notice,
                        message: model.message,
                        childName: model.session.childName,
                        isSaving: model.isSaving,
                        canSave: model.canSave
                    ) {
                        Task { await model.save() }
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
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    /// Three segments, a fourth only for a rule saved as "Doim yopiq". A mode
    /// this app does not know lights none until the parent picks one (the
    /// selection is nil, and no label is ever made for `.unknown`). Tapping
    /// the lit segment again is no event: `setMode` runs only for a change.
    private var modePicker: some View {
        Picker(
            l10n.appRulesEdit(model.name),
            selection: Binding(
                get: { model.selectedMode },
                set: { mode in
                    if let mode, mode != model.selectedMode { model.setMode(mode) }
                }
            )
        ) {
            ForEach(model.modes, id: \.self) { mode in
                Text(AppRuleTexts.modeLabel(mode, l10n))
                    .tag(mode as AppPolicyMode?)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(l10n.appRulesEdit(model.name))
    }
}
