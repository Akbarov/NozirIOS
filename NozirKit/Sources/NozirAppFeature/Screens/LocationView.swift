import MapKit
import SwiftUI
import NozirDesignSystem
import NozirL10n
import NozirLocation

/// P13 as Android `LocationContent`: the switcher, the map, what is known about
/// where the child is, "where are they now", the zones and the tracking rule.
struct LocationView: View {
    @State private var model: LocationModel
    private let onOpenZone: (UUID, SafeZone?) -> Void
    private let onOpenTracking: (UUID) -> Void
    private let onAddChild: () -> Void
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase
    @State private var position: MapCameraPosition

    init(
        model: LocationModel,
        onOpenZone: @escaping (UUID, SafeZone?) -> Void,
        onOpenTracking: @escaping (UUID) -> Void,
        onAddChild: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        _position = State(initialValue: MapCamera.region(model.cameraTarget ?? LocationModel.fallbackCentre, metres: model.snapshot?.coordinate == nil ? 2500 : 1200))
        self.onOpenZone = onOpenZone
        self.onOpenTracking = onOpenTracking
        self.onAddChild = onAddChild
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.medium) {
                if model.showsSwitcher {
                    NozirChildSwitcher(
                        children: model.switcherChildren(l10n),
                        selection: Binding(get: { model.childId }, set: { model.selectedChildId = $0 }),
                        fallbackInitial: l10n.previewAvatarInitial
                    )
                }
                content
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenMapTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.childId) { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.load() }
            } else {
                model.cancelRequest()
            }
        }
        .onDisappear { model.cancelRequest() }
        .onChange(of: model.cameraTarget) { _, target in
            guard let target else { return }
            position = MapCamera.region(target, metres: model.snapshot?.coordinate == nil ? 2500 : 1200)
        }
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        case .noChild:
            NozirEmptyState(
                title: l10n.locationNoChildTitle,
                message: l10n.locationNoChildBody,
                actionTitle: l10n.homeEmptyAction,
                action: onAddChild
            )
        case .locked:
            LocationLockCard()
            // Deleting is never restricted: a lapsed plan keeps its zones reachable.
            if !model.zones.isEmpty {
                lockedZoneChips
            }
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        case .ready, .neverReported:
            located
        }
    }

    @ViewBuilder
    private var located: some View {
        if model.isOffline {
            NozirOfflineNotice(l10n.stateOfflineNotice)
        }
        if let message = model.inlineMessage {
            NozirInlineMessage(message.text(l10n))
        }
        LocationMapView(
            pin: model.snapshot?.coordinate,
            pinTitle: model.child?.displayName ?? "",
            isStale: model.snapshot?.isStale ?? false,
            zones: model.zones,
            currentZoneId: model.snapshot?.zoneId,
            position: $position
        )
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: NozirRadius.cardCompact))
        .accessibilityLabel(l10n.locationMapDescription)
        statusCard
        requestSection
        zoneChips
        if let childId = model.childId {
            NozirCard {
                NozirSettingsRow(l10n.locationTrackingToggleTitle, value: LocationTexts.tracking(model.tracking, l10n)) {
                    onOpenTracking(childId)
                }
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let snapshot = model.snapshot {
                NozirCard(tone: snapshot.isStale ? .attention : .plain) {
                    if snapshot.coordinate != nil {
                        Text(LocationTexts.headline(snapshot, childName: model.child?.displayName, l10n)).nozirText(.titleSmall)
                        if let updated = LocationTexts.updated(snapshot, now: context.date, l10n) {
                            Text(updated).nozirText(.bodySmall, color: NozirColor.textSecondary)
                        }
                        HStack(spacing: NozirSpacing.medium) {
                            if let accuracy = LocationTexts.accuracy(snapshot.accuracyMeters, l10n) {
                                Text(accuracy).nozirText(.bodySmall, color: NozirColor.textSecondary)
                            }
                            if let battery = LocationTexts.battery(snapshot.batteryPercent, l10n) {
                                Text(battery).nozirText(.bodySmall, color: NozirColor.textSecondary)
                            }
                        }
                    } else {
                        Text(l10n.locationUnknownTitle).nozirText(.titleSmall)
                    }
                    if let reason = snapshot.unavailableReason {
                        Text(LocationTexts.unavailable(reason, l10n)).nozirText(.body)
                        if let when = LocationTexts.unavailableWhen(snapshot.unavailableAt, now: context.date, l10n) {
                            Text(when).nozirText(.bodySmall, color: NozirColor.textSecondary)
                        }
                    }
                    if snapshot.isStale, snapshot.coordinate != nil {
                        Text(l10n.locationStaleNote).nozirText(.bodySmall, color: NozirColor.attentionContent)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                NozirEmptyState(title: l10n.locationNeverReportedTitle, message: l10n.locationNeverReportedBody)
            }
        }
    }

    @ViewBuilder
    private var requestSection: some View {
        NozirButton(l10n.locationRequestFix, variant: .secondary, isLoading: model.request == .waiting) {
            model.startRequest()
        }
        .disabled(model.request == .waiting)
        switch model.request {
        case .idle:
            EmptyView()
        case .waiting:
            Text(l10n.locationRequestWaiting).nozirText(.bodySmall, color: NozirColor.textSecondary)
        case .unreachable:
            NozirInlineMessage(l10n.locationRequestUnreachable)
        case .failed(let message):
            NozirInlineMessage(message.text(l10n))
        }
    }

    private var zoneChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NozirSpacing.small) {
                ForEach(model.zones) { zone in
                    chip(LocationTexts.zoneChip(zone, l10n), highlighted: zone.id == model.snapshot?.zoneId) {
                        if let childId = model.childId { onOpenZone(childId, zone) }
                    }
                }
                chip(l10n.locationAddZone, highlighted: false) {
                    if let childId = model.childId { onOpenZone(childId, nil) }
                }
            }
        }
    }

    private var lockedZoneChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NozirSpacing.small) {
                ForEach(model.zones) { zone in
                    chip(LocationTexts.zoneChip(zone, l10n), highlighted: false) {
                        if let childId = model.childId { onOpenZone(childId, zone) }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .nozirText(.bodySmall, color: highlighted ? NozirColor.goodContent : NozirColor.primaryAccent)
                .padding(.horizontal, NozirSpacing.compact)
                .padding(.vertical, NozirSpacing.small)
                .background(Capsule().fill(highlighted ? NozirColor.goodContainer : NozirColor.primaryContainer))
        }
        .buttonStyle(.plain)
    }
}
