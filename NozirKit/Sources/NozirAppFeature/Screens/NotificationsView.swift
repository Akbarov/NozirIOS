import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P16 as Android `NotificationsContent`: the filter, the offline notice, the
/// record (or its spinner, error or empty state), "Yana koʻrsatish", then the
/// "Telefon jim qolsa" card once the settings are read. No push note: iOS has
/// no push yet (spec §1). A tapped row is read at once; one that leads
/// somewhere pushes onto Home's stack.
struct NotificationsView: View {
    @State private var model: NotificationsModel
    private let onOpen: (SignedInView.HomeStep) -> Void
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase

    init(model: NotificationsModel, onOpen: @escaping (SignedInView.HomeStep) -> Void) {
        _model = State(initialValue: model)
        self.onOpen = onOpen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.small) {
                Picker(l10n.screenNotificationsTitle, selection: Binding(
                    get: { model.filter },
                    set: { filter in Task { await model.setFilter(filter) } }
                )) {
                    Text(l10n.notificationsFilterAll).tag(NotificationFilter.all)
                    Text(l10n.notificationsFilterImportant).tag(NotificationFilter.important)
                }
                .pickerStyle(.segmented)
                if model.isOffline {
                    NozirOfflineNotice(l10n.stateOfflineNotice)
                }
                content
                if let minutes = model.offlineAfterMinutes {
                    offlineCard(minutes)
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenNotificationsTitle)
        .navigationBarTitleDisplayMode(.inline)
        // On open and on coming back from a screen a row opened (spec §5.2).
        .task { await model.appear() }
        .refreshable { await model.load() }
        // Back from another app: there is no push yet, so this is how news arrives.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.load() }
            }
        }
        .nozirToast(Binding(
            get: { model.toast?.text(l10n) },
            set: { if $0 == nil { model.toast = nil } }
        ))
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        case .ready:
            if model.isEmpty {
                NozirEmptyState(
                    title: NotificationTexts.emptyTitle(model.filter, l10n),
                    message: NotificationTexts.emptyBody(model.filter, l10n)
                )
            } else {
                list
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        let now = Date()
        ForEach(model.items) { notification in
            NotificationRow(notification: notification, now: now) {
                if let step = model.open(notification) {
                    onOpen(step)
                }
            }
        }
        if let message = model.inlineMessage {
            NozirInlineMessage(message.text(l10n))
        }
        if model.hasMore {
            NozirButton(l10n.notificationsLoadMore, variant: .ghost, isLoading: model.isLoadingMore) {
                Task { await model.loadMore() }
            }
            .disabled(model.isLoadingMore || model.isRefreshing)
        }
    }

    /// Android `DeviceOfflineSetting`: a value that is not a preset still reads
    /// right on the line below; the control then shows nothing selected.
    private func offlineCard(_ minutes: Int) -> some View {
        NozirCard {
            Text(l10n.notificationsOfflineTitle)
                .nozirText(.titleSmall)
                .accessibilityAddTraits(.isHeader)
            Text(l10n.notificationsOfflineBody)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            Picker(l10n.notificationsOfflineTitle, selection: Binding(
                get: { minutes },
                set: { chosen in Task { await model.setOfflineAfter(minutes: chosen) } }
            )) {
                ForEach(NotificationTexts.offlinePresets, id: \.self) { preset in
                    Text(NotificationTexts.presetLabel(preset, l10n))
                        .accessibilityLabel(NotificationTexts.presetAccessibilityLabel(preset, l10n))
                        .tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.pendingOfflineMinutes != nil)
            Text(NotificationTexts.offlineCurrent(minutes, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
    }
}
