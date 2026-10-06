import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P10 as Android `BedtimeContent`: the window, the nights, the warning, and
/// what keeps working at night (read only).
struct BedtimeView: View {
    @State private var model: BedtimeModel
    @Environment(\.l10n) private var l10n

    init(model: BedtimeModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                if let bedtime = model.bedtime {
                    if model.session.isOffline {
                        NozirOfflineNotice(l10n.stateOfflineNotice)
                    }
                    NozirCard {
                        HStack(spacing: NozirSpacing.medium) {
                            RuleTimePicker(l10n.bedtimeStartLabel, time: Binding(get: { bedtime.start }, set: { model.setStart($0) }))
                            RuleTimePicker(l10n.bedtimeEndLabel, time: Binding(get: { bedtime.end }, set: { model.setEnd($0) }))
                        }
                        Text(l10n.bedtimeLength(Durations.long(bedtime.lengthMinutes, l10n)))
                            .nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                    NozirCard {
                        RuleDaysSection(activeDays: Set(bedtime.activeDays)) { model.toggleDay($0) }
                    }
                    NozirCard {
                        RuleWindDownSection(
                            minutes: bedtime.windDownMinutes,
                            onToggle: { model.setWindDown(on: $0) },
                            onMinutes: { model.setWindDownMinutes($0) }
                        )
                    }
                    allowlistCard
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
        .navigationTitle(l10n.screenSleepTimeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    /// Android `BedtimeAllowlistCard`: fixed on the phone, nothing to edit.
    private var allowlistCard: some View {
        NozirCard {
            Text(l10n.bedtimeAllowlistLabel).nozirText(.titleSmall)
            NozirBulletRow(l10n.bedtimeAllowlistCalls)
            NozirBulletRow(l10n.bedtimeAllowlistSos)
            NozirBulletRow(l10n.bedtimeAllowlistParent)
            NozirBulletRow(l10n.bedtimeAllowlistAlarm)
        }
    }
}
