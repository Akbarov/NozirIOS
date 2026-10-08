import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P19 as Android `SubscriptionContent`: the offline notice, what the family
/// has, then the "Nozir PRO faol" card or the two plans; the pay action and
/// the SOS note pinned below the scroll (inside it at accessibility text
/// sizes, as P20 does, so nothing is squeezed). The page opens in Safari;
/// nothing here grants anything — the server does when Click says the money moved.
struct SubscriptionView: View {
    @State private var model: SubscriptionModel
    @Environment(\.l10n) private var l10n
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: SubscriptionModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
          VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: NozirSpacing.compact) {
                if model.isOffline {
                    NozirOfflineNotice(l10n.stateOfflineNotice)
                }
                stateNotes
                if case .active(_, let endsAt, let autoRenew)? = model.state {
                    activeCard(endsAt: endsAt, autoRenew: autoRenew)
                    features
                } else {
                    offer
                }
            }
            .padding(NozirSpacing.medium)
            if dynamicTypeSize.isAccessibilitySize {
                footer
            }
          }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                footer
            }
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.subscriptionTopBar)
        .navigationBarTitleDisplayMode(.inline)
        // Every entry reads again (spec D2).
        .task { await model.load() }
        .refreshable { await model.load() }
        // Back from Safari: iOS paused the watch while the parent paid.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.sceneBecameActive() }
            }
        }
        .onChange(of: model.checkoutURLToOpen) { _, url in
            if let url { open(url) }
        }
        // The flip to PRO is otherwise silent for VoiceOver.
        .onChange(of: model.isActive) { _, active in
            if active {
                AccessibilityNotification.Announcement(l10n.subscriptionActiveTitle).post()
            }
        }
        .onDisappear { model.stopWatching() }
    }

    /// Safari, or the Click app if it claims the link (Android `ACTION_VIEW`).
    private func open(_ url: URL) {
        openURL(url) { accepted in
            Task { @MainActor in model.checkoutOpened(accepted) }
        }
    }

    // MARK: What the family has

    @ViewBuilder
    private var stateNotes: some View {
        switch model.state {
        case .trial(let endsAt)?:
            NozirInlineMessage(SubscriptionTexts.trialLine(endsAt: endsAt, calendar: model.calendar, l10n))
            NozirInlineMessage(l10n.subscriptionTrialBody)
        case .grace(_, _, let until)?:
            NozirInlineMessage(SubscriptionTexts.graceLine(until: until, calendar: model.calendar, l10n))
        case .expired?:
            NozirInlineMessage(l10n.subscriptionExpiredTitle)
        case .free?, .active?, nil:
            EmptyView()
        }
    }

    /// "Nozir PRO faol", the cadence when the plan is still listed, the end
    /// date (the point: it answers "am I about to be charged?"), and renewal.
    private func activeCard(endsAt: Date?, autoRenew: Bool) -> some View {
        NozirCard(tone: .good) {
            HStack(spacing: NozirSpacing.compact) {
                Text(l10n.glyphCheck)
                    .nozirText(.titleSmall, color: NozirColor.goodContent)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: NozirRadius.cardCompact).fill(NozirColor.card))
                    .accessibilityHidden(true)
                Text(l10n.subscriptionActiveTitle)
                    .nozirText(.titleSmall)
                    .accessibilityAddTraits(.isHeader)
            }
            if let period = model.activePeriod {
                Text(SubscriptionTexts.activePeriod(period, l10n)).nozirText(.body)
            }
            Text(SubscriptionTexts.activeUntil(endsAt: endsAt, calendar: model.calendar, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            Text(SubscriptionTexts.autoRenew(autoRenew, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
    }

    @ViewBuilder
    private var features: some View {
        if !model.features.isEmpty {
            NozirSectionTitle(l10n.subscriptionFeaturesLabel)
            ForEach(Array(model.features.enumerated()), id: \.offset) { _, feature in
                NozirBulletRow(feature)
            }
        }
    }

    // MARK: The offer

    @ViewBuilder
    private var offer: some View {
        if !model.plans.isEmpty {
            // A refused checkout is said above the offer, which stays.
            if let note = model.message {
                NozirInlineMessage(note.text(l10n))
            }
            if let yearly = model.yearly {
                planCard(
                    yearly,
                    caption: SubscriptionTexts.monthlyEquivalent(yearlySom: yearly.priceSom, l10n),
                    badge: model.savingPercent.map { l10n.subscriptionSavingBadge($0) }
                )
            }
            if let monthly = model.monthly {
                planCard(monthly, caption: nil, badge: nil)
            }
            features
        } else if case .failed(let problem) = model.phase {
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: problem.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        } else if model.phase == .loading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityLabel(l10n.contentDescriptionLoading)
        } else {
            NozirEmptyState(title: l10n.subscriptionPlansEmptyTitle, message: l10n.subscriptionPlansEmptyBody)
        }
    }

    /// A radio choice (Android `SubscriptionPlanCard`): teal when chosen, the
    /// badge overhanging the top edge.
    private func planCard(_ plan: SubscriptionPlan, caption: String?, badge: String?) -> some View {
        let isSelected = model.selectedPeriod == plan.period
        return Button {
            model.select(plan.period)
        } label: {
            NozirCard(tone: isSelected ? .selected : .plain) {
                planRow(plan, caption: caption, isSelected: isSelected)
            }
            .overlay(alignment: .topTrailing) {
                if let badge {
                    NozirBadge(badge)
                        .padding(.trailing, 14)
                        .offset(y: -11)
                }
            }
            .padding(.top, badge == nil ? 0 : 11)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Name and caption beside the price; stacked at accessibility text sizes.
    private func planRow(_ plan: SubscriptionPlan, caption: String?, isSelected: Bool) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NozirSpacing.extraSmall))
            : AnyLayout(HStackLayout(alignment: .top, spacing: NozirSpacing.compact))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(SubscriptionTexts.planName(plan.period, l10n)).nozirText(.titleSmall)
                if let caption {
                    Text(caption).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
            }
            if !stacked {
                Spacer(minLength: 0)
            }
            VStack(alignment: stacked ? .leading : .trailing, spacing: 2) {
                Text(SubscriptionTexts.grouped(plan.priceSom))
                    .nozirText(.titleLarge, color: isSelected ? NozirColor.primaryAccent : NozirColor.textPrimary)
                Text(SubscriptionTexts.priceUnit(plan.period, l10n))
                    .nozirText(.bodySmall, color: NozirColor.textSecondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: NozirSpacing.compact) {
            if model.offersPlans {
                if model.isOwner {
                    payAction
                } else {
                    // Spec D3: a guardian is told why, instead of a button the server refuses.
                    Text(l10n.iosSubscriptionOwnerOnly)
                        .nozirText(.bodySmall, color: NozirColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            Text(l10n.subscriptionSosFree)
                .nozirText(.bodySmall, color: NozirColor.goodContent)
                .multilineTextAlignment(.center)
            Text(l10n.subscriptionSosFreeBody)
                .nozirText(.bodySmall, color: NozirColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, NozirSpacing.medium)
        .padding(.vertical, NozirSpacing.compact)
        .frame(maxWidth: .infinity)
        .background(NozirColor.background)
    }

    /// Android `PayAction`: ready → "Click orqali toʻlash · 7 500 soʻm" (and,
    /// once a page was opened, the wait and the check); no live channel → a
    /// disabled button, why, and the channels being prepared.
    @ViewBuilder
    private var payAction: some View {
        if let channel = model.payChannel, let plan = model.selectedPlan {
            NozirButton(
                SubscriptionTexts.payTitle(channel: channel, priceSom: plan.priceSom, l10n),
                size: .callToAction,
                isLoading: model.isStartingCheckout
            ) {
                Task { await model.pay() }
            }
            if model.isAwaitingPayment {
                Text(l10n.subscriptionAwaitingPayment)
                    .nozirText(.bodySmall, color: NozirColor.textSecondary)
                    .multilineTextAlignment(.center)
                NozirButton(l10n.subscriptionCheckPayment, variant: .secondary) {
                    Task { await model.checkPayment() }
                }
            }
        } else {
            NozirButton(l10n.subscriptionActionPay, size: .callToAction) {}
                .disabled(true)
            Text(l10n.subscriptionPaymentNotReady)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
            if !model.plannedChannels.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: NozirSpacing.extraSmall) { channelChips }
                    VStack(spacing: NozirSpacing.extraSmall) { channelChips }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Labels, not buttons: nothing here starts anything.
    private var channelChips: some View {
        ForEach(model.plannedChannels, id: \.self) { channel in
            Text(SubscriptionTexts.channelName(channel, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .padding(.horizontal, NozirSpacing.small)
                .padding(.vertical, NozirSpacing.extraSmall)
                .background(Capsule().fill(NozirColor.card))
                .overlay(Capsule().strokeBorder(NozirColor.border, lineWidth: 1))
        }
    }
}
