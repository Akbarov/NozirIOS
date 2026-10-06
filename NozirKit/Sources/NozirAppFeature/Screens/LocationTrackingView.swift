import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P12b as Android `LocationTrackingContent`: on/off and three segmented
/// choices; the numbers stay while it is off.
struct LocationTrackingView: View {
    @State private var model: LocationTrackingModel
    @Environment(\.l10n) private var l10n

    init(model: LocationTrackingModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                if let tracking = model.tracking {
                    form(tracking)
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
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenLocationTrackingTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    @ViewBuilder
    private func form(_ tracking: LocationTracking) -> some View {
        NozirCard {
            Toggle(l10n.locationTrackingToggleTitle, isOn: Binding(get: { tracking.isEnabled }, set: { model.setEnabled($0) }))
                .tint(NozirColor.primary)
            Text(tracking.isEnabled ? l10n.locationTrackingOn : l10n.locationTrackingOff)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        if tracking.isEnabled {
            choice(
                title: l10n.locationTrackingIntervalTitle,
                body: l10n.locationTrackingIntervalBody,
                values: LocationTracking.intervalChoices,
                selection: Binding(get: { tracking.intervalMinutes }, set: { model.setInterval($0) }),
                label: l10n.locationTrackingMinutes
            )
            choice(
                title: l10n.locationTrackingZoneIntervalTitle,
                body: l10n.locationTrackingZoneIntervalBody,
                values: LocationTracking.zoneIntervalChoices,
                selection: Binding(get: { tracking.zoneIntervalMinutes }, set: { model.setZoneInterval($0) }),
                label: l10n.locationTrackingMinutes
            )
            choice(
                title: l10n.locationTrackingMoveTitle,
                body: l10n.locationTrackingMoveBody,
                values: LocationTracking.moveChoices,
                selection: Binding(get: { tracking.moveMetres }, set: { model.setMove($0) }),
                label: l10n.locationTrackingMetres
            )
        }
        switch model.notice {
        case .saved?:
            Text(model.childName.map(l10n.rulesSavedNamed) ?? l10n.rulesSaved)
                .nozirText(.bodySmall, color: NozirColor.goodContent)
        case .conflict?:
            NozirInlineMessage(l10n.rulesConflictNotice)
        case nil:
            EmptyView()
        }
        if model.message == .subscriptionRequired {
            LocationLockCard()
        } else if let message = model.message {
            NozirInlineMessage(message.text(l10n))
        }
        NozirButton(l10n.safeZoneSave, size: .callToAction, isLoading: model.isSaving) {
            Task { await model.save() }
        }
        .disabled(!model.canSave)
    }

    private func choice(
        title: String,
        body: String,
        values: [Int],
        selection: Binding<Int>,
        label: @escaping (Int) -> String
    ) -> some View {
        NozirCard {
            Text(title).nozirText(.titleSmall)
            Text(body).nozirText(.bodySmall, color: NozirColor.textSecondary)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
