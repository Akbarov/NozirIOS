import SwiftUI
import NozirDesignSystem
import NozirL10n

/// A screen opened from P09, carrying P09's session so every save there moves
/// the one version all of the child's rules share.
enum RuleScreen: Hashable {
    case bedtime(ChildRulesSession)
    /// P11, the list of app rules.
    case apps(ChildRulesSession)
    /// One app's editor, opened from P11; `displayName` is the phone's name for it when known.
    case appRule(ChildRulesSession, packageId: String, displayName: String?)
    case bonus(ChildRulesSession)
    case locationTracking(ChildRulesSession)
}

/// P09 — the rules hub: the switcher (from Profile, 2+ children) and the
/// chosen child's daily limit.
struct RulesHubView: View {
    @State private var model: RulesHubModel
    private let onOpen: (RuleScreen) -> Void
    @Environment(\.l10n) private var l10n

    init(model: RulesHubModel, onOpen: @escaping (RuleScreen) -> Void) {
        _model = State(initialValue: model)
        self.onOpen = onOpen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                if model.showsSwitcher {
                    NozirChildSwitcher(
                        children: model.switcherChildren(l10n),
                        selection: Binding(get: { model.selectedChildId }, set: { model.select($0) }),
                        fallbackInitial: l10n.previewAvatarInitial
                    )
                }
                if let dailyLimit = model.dailyLimit {
                    DailyLimitSection(model: dailyLimit, onOpen: onOpen)
                } else {
                    NozirEmptyState(title: l10n.rulesNoChildTitle, message: l10n.rulesNoChildBody)
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenDailyLimitTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Once per child: a tab switch finds the session loaded and the edit untouched.
        .task(id: model.selectedChildId) { await model.load() }
        .refreshable { await model.refresh() }
    }
}
