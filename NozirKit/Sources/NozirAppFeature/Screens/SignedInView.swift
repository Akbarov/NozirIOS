import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirInsights
import NozirL10n
import NozirLocation

/// The signed-in app: Home, Statistics, Location and Profile.
struct SignedInView: View {
    enum HomeStep: Hashable {
        /// P06 for a child; `date` nil is the latest finished day.
        case summary(UUID, String, date: LocalDate? = nil)
        /// P07 for a child; `weekStart` nil is this week.
        case weekly(UUID, weekStart: LocalDate? = nil)
        case apps(UUID)
        case details(Child)
        case sos(ActiveSos)
        /// P09 from P03: that child, no switcher.
        case rules(UUID)
        case ruleScreen(RuleScreen)
        /// P17 from a Home row, with that child's minutes today (plan deviation T1).
        case timeRequest(UUID, usedMinutesToday: Int?)
        /// P18 for that child, from the Home row or the child's page.
        case protection(UUID)
        /// P16, from Home's bell or Profile's row (spec D1: its links push onto Home's stack).
        case notifications
        /// P16a: a summary notification, until the server says which day or
        /// week it is; then replaced by that step (the id is the summary's).
        case summaryLink(UUID)
    }

    enum StatisticsStep: Hashable {
        case apps(UUID)
    }

    enum LocationStep: Hashable {
        /// A child's zone to edit, or nil for a new one.
        case zone(UUID, UUID?)
        case tracking(UUID)
    }

    enum ProfileStep: Hashable {
        case child(Child)
        case pairing(Child)
        /// P09 from the Profile row: nil opens on the first child, with the switcher.
        case rules(UUID?)
        /// P09 from P03 opened in this tab: that child, no switcher.
        case childRules(UUID)
        case ruleScreen(RuleScreen)
        /// P20 from the Profile settings card.
        case privacy
        /// P18 from the child's page opened in this tab.
        case protection(UUID)
    }

    @State private var model: SignedInModel
    @State private var homePath: [HomeStep] = []
    @State private var statisticsPath: [StatisticsStep] = []
    @State private var locationPath: [LocationStep] = []
    @State private var profilePath: [ProfileStep] = []
    @Environment(\.l10n) private var l10n
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    init(model: SignedInModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        TabView(selection: $model.tab) {
            NavigationStack(path: $homePath) {
                HomeView(
                    model: model.makeHomeModel(),
                    reloadToken: model.homeRefresh,
                    emergencyNumber: { model.currentEmergencyNumber },
                    onOpenSummary: { homePath.append(.summary($0, $1)) },
                    onOpenSos: { homePath.append(.sos($0)) },
                    onOpenTimeRequest: { homePath.append(.timeRequest($0, usedMinutesToday: $1)) },
                    onOpenProtection: { homePath.append(.protection($0)) },
                    onOpenNotifications: { openNotifications() },
                    onAddChild: { model.presentAddChild() }
                )
                .navigationDestination(for: HomeStep.self) { step in
                    homeDestination(step)
                }
            }
            .tabItem { Label(l10n.tabHome, systemImage: "house") }
            .tag(SignedInModel.Tab.home)

            NavigationStack(path: $statisticsPath) {
                StatisticsView(
                    statistics: model.statistics,
                    makeWeekly: { model.makeWeeklyModel(childId: $0) },
                    onAddChild: { model.presentAddChild() },
                    onOpenApps: { statisticsPath.append(.apps($0)) }
                )
                .navigationDestination(for: StatisticsStep.self) { step in
                    switch step {
                    case .apps(let childId):
                        AppUsageView(model: model.makeAppUsageModel(childId: childId))
                    }
                }
            }
            .tabItem { Label(l10n.tabStatistics, systemImage: "chart.bar") }
            .tag(SignedInModel.Tab.statistics)

            NavigationStack(path: $locationPath) {
                LocationView(
                    model: model.locationTab,
                    onOpenZone: { childId, zone in locationPath.append(.zone(childId, zone?.id)) },
                    onOpenTracking: { locationPath.append(.tracking($0)) },
                    onAddChild: { model.presentAddChild() }
                )
                .navigationDestination(for: LocationStep.self) { step in
                    switch step {
                    case .zone(let childId, let zoneId):
                        SafeZoneView(
                            model: model.makeSafeZoneModel(childId: childId, zoneId: zoneId),
                            onFinished: { locationPath.removeAll() }
                        )
                    case .tracking(let childId):
                        LocationTrackingView(model: model.makeLocationTrackingModel(childId: childId))
                    }
                }
            }
            .tabItem { Label(l10n.tabLocation, systemImage: "location") }
            .tag(SignedInModel.Tab.location)

            NavigationStack(path: $profilePath) {
                ProfileView(
                    model: model.makeProfileModel(),
                    onAddChild: { model.presentAddChild() },
                    onOpenChild: { profilePath.append(.child($0)) },
                    onPair: { profilePath.append(.pairing($0)) },
                    onOpenRules: { profilePath.append(.rules(nil)) },
                    onOpenNotifications: { openNotifications() },
                    onOpenPrivacy: { profilePath.append(.privacy) }
                )
                .navigationDestination(for: ProfileStep.self) { step in
                    profileDestination(step)
                }
            }
            .tabItem { Label(l10n.tabProfile, systemImage: "person.crop.circle") }
            .tag(SignedInModel.Tab.profile)
        }
        .tint(NozirColor.primary)
        .fullScreenCover(isPresented: $model.isAddingChild) {
            AddChildFlow(model: model, onClose: {
                clearPaths()
                model.finishAddChild()
            })
                // Said again for the cover, so it cannot fall back to the defaults.
                .environment(\.l10n, l10n)
                .environment(\.locale, locale)
        }
        .task(id: scenePhase == .active) { if scenePhase == .active { await model.start() } }
    }

    private func clearPaths() {
        homePath.removeAll()
        statisticsPath.removeAll()
        locationPath.removeAll()
        profilePath.removeAll()
    }

    /// P16 always lives on Home's stack, so a row's link pushes where that
    /// screen belongs; from Profile the tab switches first (spec D1). Never
    /// stacked twice (plan deviation N9).
    private func openNotifications() {
        model.tab = .home
        if homePath.last != .notifications {
            homePath.append(.notifications)
        }
    }

    @ViewBuilder
    private func homeDestination(_ step: HomeStep) -> some View {
        switch step {
        case .summary(let childId, let childName, let date):
            DailySummaryView(
                model: model.makeDailySummaryModel(childId: childId, childName: childName, date: date),
                onEditChild: {
                    if let child = model.family.child(childId) {
                        homePath.append(.details(child))
                    }
                },
                onOpenWeekly: { homePath.append(.weekly(childId)) }
            )
        case .weekly(let childId, let weekStart):
            WeeklyReportView(
                model: model.makeWeeklyModel(childId: childId, weekStart: weekStart),
                switcher: nil,
                onOpenApps: { homePath.append(.apps($0)) }
            )
        case .apps(let childId):
            AppUsageView(model: model.makeAppUsageModel(childId: childId))
        case .details(let child):
            ChildDetailsView(
                model: model.makeDetailsModel(child),
                onRemoved: { clearPaths() },
                onOpenRules: { homePath.append(.rules(child.id)) },
                onOpenProtection: { homePath.append(.protection(child.id)) }
            )
        case .sos(let seed):
            SosDetailView(model: model.makeSosDetailModel(
                seed: seed,
                emergencyNumber: SosDetailModel.dialNumber(configured: model.currentEmergencyNumber, fallback: l10n.sosEmergencyNumber)
            ))
        case .rules(let childId):
            RulesHubView(
                model: model.makeRulesHubModel(childId: childId, picksChild: false),
                onOpen: { homePath.append(.ruleScreen($0)) }
            )
        case .ruleScreen(let screen):
            ruleDestination(screen) { homePath.append(.ruleScreen($0)) }
        case .timeRequest(let id, let usedMinutesToday):
            TimeRequestView(model: model.makeTimeRequestModel(id: id, usedMinutesToday: usedMinutesToday))
        case .protection(let childId):
            ProtectionView(model: model.makeProtectionModel(childId: childId))
        case .notifications:
            NotificationsView(model: model.makeNotificationsModel()) { step in
                homePath.append(step)
            }
        case .summaryLink(let summaryId):
            SummaryLinkView(model: model.makeSummaryLinkModel(summaryId: summaryId)) { step in
                homePath = SummaryLinkModel.path(homePath, replacing: summaryId, with: step)
            }
        }
    }

    @ViewBuilder
    private func profileDestination(_ step: ProfileStep) -> some View {
        switch step {
        case .child(let child):
            ChildDetailsView(
                model: model.makeDetailsModel(child),
                onRemoved: { clearPaths() },
                onOpenRules: { profilePath.append(.childRules(child.id)) },
                onOpenProtection: { profilePath.append(.protection(child.id)) }
            )
        case .pairing(let child):
            PairingView(model: model.makePairingModel(child), onFinished: { profilePath.removeAll() })
        case .rules(let childId):
            RulesHubView(
                model: model.makeRulesHubModel(childId: childId, picksChild: true),
                onOpen: { profilePath.append(.ruleScreen($0)) }
            )
        case .childRules(let childId):
            RulesHubView(
                model: model.makeRulesHubModel(childId: childId, picksChild: false),
                onOpen: { profilePath.append(.ruleScreen($0)) }
            )
        case .ruleScreen(let screen):
            ruleDestination(screen) { profilePath.append(.ruleScreen($0)) }
        case .privacy:
            PrivacyView(model: model.makePrivacyModel())
        case .protection(let childId):
            ProtectionView(model: model.makeProtectionModel(childId: childId))
        }
    }

    /// P10, P11, P12 and P12b on the session of the hub that opened them, and
    /// P11's editor on the same one. Each view keeps the first model it is
    /// given (`@State(initialValue:)`), like SafeZoneView. `onOpen` pushes onto
    /// the tab this screen is in.
    @ViewBuilder
    private func ruleDestination(_ screen: RuleScreen, onOpen: @escaping (RuleScreen) -> Void) -> some View {
        switch screen {
        case .bedtime(let session):
            BedtimeView(model: model.makeBedtimeModel(session: session))
        case .apps(let session):
            AppRulesView(model: model.makeAppRulesModel(session: session)) { target in
                onOpen(.appRule(session, packageId: target.packageId, displayName: target.displayName))
            }
        case .appRule(let session, let packageId, let displayName):
            AppRuleView(model: model.makeAppRuleModel(session: session, packageId: packageId, displayName: displayName))
        case .bonus(let session):
            BonusView(model: model.makeBonusModel(session: session))
        case .locationTracking(let session):
            LocationTrackingView(model: model.makeLocationTrackingModel(session: session))
        }
    }
}
