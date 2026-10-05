import MapKit
import SwiftUI
import NozirDesignSystem
import NozirL10n
import NozirLocation

/// P15 as Android `SosAlertContent`: who and when, battery and connection,
/// where (a still map), the calls, and "I have seen it".
struct SosDetailView: View {
    @State private var model: SosDetailModel
    @Environment(\.l10n) private var l10n
    @Environment(\.openURL) private var openURL
    @State private var actionUnavailable = false

    init(model: SosDetailModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: NozirSpacing.large) {
                    header(now: context.date)
                    switch model.phase {
                    case .missing:
                        NozirEmptyState(title: l10n.sosNotFoundTitle, message: l10n.sosNotFoundBody)
                    case .failed(let message):
                        NozirErrorState(
                            title: l10n.stateErrorTitle,
                            message: message.text(l10n),
                            retryTitle: l10n.stateActionRetry
                        ) {
                            Task { await model.load() }
                        }
                    case .loading, .ready:
                        if model.isOffline {
                            NozirOfflineNotice(l10n.stateOfflineNotice)
                        }
                        if let detail = model.detail {
                            facts(detail)
                            locationCard(detail, now: context.date)
                        }
                    }
                    actions
                    acknowledgeRow
                }
                .padding(NozirSpacing.medium)
            }
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenSosAlertTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func header(now: Date) -> some View {
        NozirCard(tone: .critical) {
            Text(LocationTexts.sosTitle(childName: model.childName, l10n)).nozirText(.titleLarge, color: NozirColor.criticalContent)
            Text(LocationTexts.sosMeta(triggeredAt: model.triggeredAt, now: now, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func facts(_ detail: SosAlertDetail) -> some View {
        HStack(spacing: NozirSpacing.small) {
            fact(l10n.sosFactBattery, LocationTexts.sosBattery(detail.batteryPercent, l10n))
            fact(l10n.sosFactConnection, LocationTexts.sosConnection(online: detail.deviceOnline, l10n))
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        NozirCard {
            Text(label).nozirText(.label, color: NozirColor.textSecondary)
            Text(value).nozirText(.titleSmall)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func locationCard(_ detail: SosAlertDetail, now: Date) -> some View {
        NozirCard {
            Text(l10n.sosLocationLabel).nozirText(.label, color: NozirColor.textSecondary)
            if let coordinate = detail.coordinate {
                Map(initialPosition: MapCamera.region(coordinate, metres: 600), interactionModes: []) {
                    if let accuracy = detail.accuracyMeters {
                        MapCircle(center: CLLocationCoordinate2D(coordinate), radius: accuracy)
                            .foregroundStyle(NozirColor.criticalContent.opacity(0.14))
                            .stroke(NozirColor.criticalContent.opacity(0.55), lineWidth: 3)
                    }
                    Marker("", coordinate: CLLocationCoordinate2D(coordinate))
                        .tint(NozirColor.criticalContent)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: NozirRadius.cardCompact))
                .accessibilityLabel(l10n.contentDescriptionSosLocation)
                if let place = LocationTexts.sosPlace(detail, l10n) {
                    Text(place).nozirText(.body)
                }
                if let accuracy = LocationTexts.sosAccuracy(detail.accuracyMeters, l10n) {
                    Text(accuracy).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
                if let age = LocationTexts.sosFixAge(detail, now: now, l10n) {
                    Text(age.text).nozirText(.bodySmall, color: age.isStale ? NozirColor.attentionContent : NozirColor.textSecondary)
                    if age.isStale {
                        Text(l10n.sosLocationStaleNote).nozirText(.bodySmall, color: NozirColor.attentionContent)
                    }
                }
            } else {
                Text(l10n.sosLocationUnknownTitle).nozirText(.titleSmall)
                Text(l10n.sosLocationUnknownBody).nozirText(.bodySmall, color: NozirColor.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        let call = model.call
        VStack(alignment: .leading, spacing: NozirSpacing.small) {
            NozirButton(call.callChildTitle(l10n), size: .callToAction) { open(call.childCallURL) }
                .disabled(call.childCallURL == nil)
            if call.childCallURL == nil {
                Text(l10n.sosCallChildUnavailable).nozirText(.bodySmall, color: NozirColor.textSecondary)
            }
        }
        if let directions = model.directionsURL {
            NozirButton(l10n.sosActionDirections, variant: .secondary) { open(directions) }
        }
        if let emergencyTitle = call.emergencyTitle(l10n) {
            NozirButton(emergencyTitle, variant: .criticalOutline, size: .callToAction) { open(call.emergencyCallURL) }
        }
        if actionUnavailable {
            NozirInlineMessage(l10n.sosActionUnavailable)
        }
    }

    @ViewBuilder
    private var acknowledgeRow: some View {
        if let detail = model.detail {
            if let settled = LocationTexts.sosSettled(detail, l10n) {
                Text(settled).nozirText(.body, color: NozirColor.goodContent)
            } else if detail.status == .active {
                NozirButton(l10n.sosAcknowledgeAction, variant: .secondary, isLoading: model.isAcknowledging) {
                    Task { await model.acknowledge() }
                }
                .disabled(!model.canAcknowledge)
                if model.acknowledgeFailed {
                    NozirInlineMessage(l10n.sosAcknowledgeFailed)
                }
            }
        }
    }

    private func open(_ url: URL?) {
        guard let url else {
            actionUnavailable = true
            return
        }
        actionUnavailable = false
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in actionUnavailable = true }
            }
        }
    }
}
