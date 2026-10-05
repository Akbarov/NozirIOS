import MapKit
import SwiftUI
import NozirDesignSystem
import NozirL10n
import NozirLocation

/// P14 as Android `SafeZoneContent`: tap the map for the centre, name it, size
/// it, choose the alerts; delete with a second question.
struct SafeZoneView: View {
    @State private var model: SafeZoneModel
    private let onFinished: () -> Void
    @Environment(\.l10n) private var l10n
    @State private var position: MapCameraPosition = MapCamera.region(LocationModel.fallbackCentre, metres: 4000)

    init(model: SafeZoneModel, onFinished: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onFinished = onFinished
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                } else if model.isMissing {
                    NozirInlineMessage(UserMessage.notFound.text(l10n))
                } else if model.loadFailed {
                    NozirErrorState(
                        title: l10n.stateErrorTitle,
                        message: (model.message ?? .serverProblem).text(l10n),
                        retryTitle: l10n.stateActionRetry
                    ) {
                        Task { await model.load() }
                    }
                } else {
                    form
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(model.isEditing ? l10n.safeZoneEditTitle : l10n.screenSafeZoneTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onChange(of: model.wasSaved || model.wasDeleted) { _, done in
            if done { onFinished() }
        }
        .onChange(of: model.isLoading) { _, loading in
            if !loading, let centre = model.centre {
                position = MapCamera.region(centre, metres: 1200)
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        MapReader { proxy in
            LocationMapView(
                pin: model.centre,
                pinTitle: model.name,
                isStale: false,
                zones: previewZone.map { [$0] } ?? [],
                currentZoneId: nil,
                position: $position
            )
            .onTapGesture { point in
                if let tapped = proxy.convert(point, from: .local) {
                    model.place(at: Coordinate(latitude: tapped.latitude, longitude: tapped.longitude))
                }
            }
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: NozirRadius.cardCompact))
        .accessibilityLabel(l10n.safeZoneMapDescription)
        if let hint = model.hint {
            Text(hintText(hint)).nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        NozirTextField(
            l10n.safeZoneNameLabel,
            text: Binding(get: { model.name }, set: { model.updateName($0) }),
            placeholder: l10n.safeZoneNamePlaceholder
        )
        VStack(alignment: .leading, spacing: NozirSpacing.small) {
            HStack {
                Text(l10n.safeZoneRadiusLabel).nozirText(.body)
                Spacer()
                Text(LocationTexts.radius(model.radius, l10n)).nozirText(.body, color: NozirColor.textSecondary)
            }
            Slider(
                value: Binding(get: { Double(model.radius) }, set: { model.updateRadius(Int($0.rounded())) }),
                in: Double(SafeZoneModel.radiusRange.lowerBound)...Double(SafeZoneModel.radiusRange.upperBound),
                step: 50
            )
            .tint(NozirColor.primary)
            .accessibilityValue(LocationTexts.radius(model.radius, l10n))
        }
        NozirCard {
            Toggle(l10n.safeZoneNotifyEnter, isOn: $model.notifyOnEnter)
            Divider()
            Toggle(l10n.safeZoneNotifyExit, isOn: $model.notifyOnExit)
            Text(l10n.safeZoneNotifyExitHint).nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        .tint(NozirColor.primary)
        if model.message == .subscriptionRequired {
            LocationLockCard()
        } else if let message = model.message {
            NozirInlineMessage(message.text(l10n))
        }
        NozirButton(l10n.safeZoneSave, size: .callToAction, isLoading: model.isSaving) {
            Task { await model.save() }
        }
        .disabled(!model.canSave)
        if model.isEditing {
            deletion
        }
    }

    @ViewBuilder
    private var deletion: some View {
        switch model.deletion {
        case .idle:
            NozirButton(l10n.safeZoneDelete, variant: .criticalOutline) { model.askToDelete() }
                .disabled(model.isSaving)
        case .confirming, .deleting:
            NozirCard(tone: .attention) {
                Text(l10n.safeZoneDeleteTitle(model.name)).nozirText(.titleSmall)
                Text(l10n.safeZoneDeleteBody).nozirText(.bodySmall)
                HStack(spacing: NozirSpacing.small) {
                    NozirButton(l10n.safeZoneDeleteCancel, variant: .secondary) { model.cancelDelete() }
                        .disabled(model.deletion == .deleting)
                    NozirButton(l10n.safeZoneDeleteConfirm, variant: .criticalOutline, isLoading: model.deletion == .deleting) {
                        Task { await model.confirmDelete() }
                    }
                    .disabled(model.isSaving)
                }
            }
        }
    }

    /// The circle as it would be saved, drawn live while the radius moves.
    private var previewZone: SafeZone? {
        guard let centre = model.centre else { return nil }
        return SafeZone(
            id: model.zoneId ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            childId: model.childId,
            name: model.name,
            latitude: centre.latitude,
            longitude: centre.longitude,
            radiusMeters: model.radius,
            notifyOnEnter: model.notifyOnEnter,
            notifyOnExit: model.notifyOnExit
        )
    }

    private func hintText(_ hint: SafeZoneModel.Hint) -> String {
        switch hint {
        case .needsPlace: l10n.safeZonePlaceHint
        case .needsName: l10n.safeZoneNameHint
        case .centredOnLastFix: l10n.safeZoneCentredHint
        }
    }
}
