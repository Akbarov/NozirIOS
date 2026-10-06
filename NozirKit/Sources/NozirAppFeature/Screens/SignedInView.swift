import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirInsights
import NozirL10n
import NozirLocation

/// The signed-in app: Home, Statistics, Location and Profile.
struct SignedInView: View {
    enum HomeStep: Hashable {
        case summary(UUID, String)
        case weekly(UUID)
        case apps(UUID)
        case details(Child)
        case sos(ActiveSos)
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
                    onPair: { profilePath.append(.pairing($0)) }
                )
                .navigationDestination(for: ProfileStep.self) { step in
                    switch step {
                    case .child(let child):
                        ChildDetailsView(model: model.makeDetailsModel(child), onRemoved: { clearPaths() })
                    case .pairing(let child):
                        PairingView(model: model.makePairingModel(child), onFinished: { profilePath.removeAll() })
                    }
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

    @ViewBuilder
    private func homeDestination(_ step: HomeStep) -> some View {
        switch step {
        case .summary(let childId, let childName):
            DailySummaryView(
                model: model.makeDailySummaryModel(childId: childId, childName: childName),
                onEditChild: {
                    if let child = model.family.child(childId) {
                        homePath.append(.details(child))
                    }
                },
                onOpenWeekly: { homePath.append(.weekly(childId)) }
            )
        case .weekly(let childId):
            WeeklyReportView(
                model: model.makeWeeklyModel(childId: childId),
                switcher: nil,
                onOpenApps: { homePath.append(.apps($0)) }
            )
        case .apps(let childId):
            AppUsageView(model: model.makeAppUsageModel(childId: childId))
        case .details(let child):
            ChildDetailsView(model: model.makeDetailsModel(child), onRemoved: { clearPaths() })
        case .sos(let seed):
            SosDetailView(model: model.makeSosDetailModel(
                seed: seed,
                emergencyNumber: SosDetailModel.dialNumber(configured: model.currentEmergencyNumber, fallback: l10n.sosEmergencyNumber)
            ))
        }
    }
}
