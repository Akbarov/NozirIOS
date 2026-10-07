import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirInsights
import NozirL10n
import NozirLocation
import NozirPrivacy

/// Everything the signed-in app shares for one session: the family, the tab,
/// and whether the add-a-child flow is up. A new sign-in gets a new one, so a
/// signed-out parent's children never linger in memory.
@MainActor
@Observable
public final class SignedInModel {
    public enum Tab: Hashable, Sendable {
        case home, statistics, location, profile
    }

    public var tab: Tab = .home
    public var isAddingChild = false
    public let family: FamilyStore
    let statistics: StatisticsModel
    /// One for the session, like Statistics: the tab keeps its chosen child.
    let locationTab: LocationModel
    /// Goes up when the add-a-child flow closes, so Home asks again.
    private(set) var homeRefresh = 0

    private let insights: any InsightsService
    let locationService: any LocationService
    private let language: LanguageStore
    private let appearance: AppearanceStore
    private let localeSync: LocaleSync
    private let emergencyNumber: @MainActor () -> String?
    private let privacy: any PrivacyService
    private let privacyConfig: @MainActor () -> PrivacyConfig
    private let signOutLocallyAction: @MainActor () -> Void
    private let signOutAction: @MainActor () async -> Void
    @ObservationIgnored private var hasStarted = false

    init(
        family: FamilyStore,
        insights: any InsightsService,
        location: any LocationService,
        language: LanguageStore,
        appearance: AppearanceStore,
        localeSync: LocaleSync,
        emergencyNumber: @escaping @MainActor () -> String?,
        privacy: any PrivacyService,
        privacyConfig: @escaping @MainActor () -> PrivacyConfig,
        signOutLocally: @escaping @MainActor () -> Void,
        signOut: @escaping @MainActor () async -> Void
    ) {
        self.family = family
        self.insights = insights
        locationService = location
        self.language = language
        self.appearance = appearance
        self.localeSync = localeSync
        self.emergencyNumber = emergencyNumber
        self.privacy = privacy
        self.privacyConfig = privacyConfig
        signOutLocallyAction = signOutLocally
        signOutAction = signOut
        statistics = StatisticsModel(family: family)
        locationTab = LocationModel(family: family, location: location)
    }

    /// After sign-in: a family with no children goes straight to adding one
    /// (on iOS `isNewAccount` is always false, so the list decides). A list that
    /// cannot be loaded opens nothing and is asked for again next time.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await localeSync.resumeIfNeeded()
        do {
            try await family.refresh()
            if family.children.isEmpty {
                isAddingChild = true
            }
        } catch {
            hasStarted = false
        }
    }

    public func presentAddChild() {
        isAddingChild = true
    }

    public func finishAddChild() {
        isAddingChild = false
        tab = .home
        homeRefresh += 1
    }

    func makeProfileModel() -> ProfileModel {
        ProfileModel(family: family, language: language, appearance: appearance, localeSync: localeSync, signOut: signOutAction)
    }

    /// P20 with the config of the moment it opens. A recorded request ends the
    /// session here only: the server has already revoked it.
    func makePrivacyModel() -> PrivacyModel {
        PrivacyModel(privacy: privacy, family: family, config: privacyConfig(), onSignedOut: signOutLocallyAction)
    }

    func makeAddChildModel() -> AddChildModel {
        AddChildModel()
    }

    func makeRulesModel(_ draft: ChildDraft) -> NewChildRulesModel {
        NewChildRulesModel(draft: draft, family: family)
    }

    func makePairingModel(_ child: Child) -> PairingModel {
        PairingModel(child: child, family: family)
    }

    func makeDetailsModel(_ child: Child) -> ChildDetailsModel {
        ChildDetailsModel(child: child, family: family)
    }

    func makeSafeZoneModel(childId: UUID, zoneId: UUID?) -> SafeZoneModel {
        SafeZoneModel(childId: childId, zoneId: zoneId, location: locationService)
    }

    func makeLocationTrackingModel(childId: UUID) -> LocationTrackingModel {
        LocationTrackingModel(childId: childId, childName: family.child(childId)?.displayName, family: family)
    }

    /// One per hub: P09 and every screen opened from it write on its version.
    func makeRulesSession(childId: UUID) -> ChildRulesSession {
        ChildRulesSession(childId: childId, family: family)
    }

    func makeDailyLimitModel(session: ChildRulesSession) -> DailyLimitModel {
        DailyLimitModel(session: session)
    }

    func makeBedtimeModel(session: ChildRulesSession) -> BedtimeModel {
        BedtimeModel(session: session)
    }

    func makeBonusModel(session: ChildRulesSession) -> BonusModel {
        BonusModel(session: session)
    }

    func makeLocationTrackingModel(session: ChildRulesSession) -> LocationTrackingModel {
        LocationTrackingModel(childId: session.childId, childName: session.childName, family: family, session: session)
    }

    /// From Profile: `childId` nil (the first child) and the switcher. From P03: that child, no switcher.
    func makeRulesHubModel(childId: UUID?, picksChild: Bool) -> RulesHubModel {
        let store = family
        return RulesHubModel(
            childId: childId,
            picksChild: picksChild,
            family: store,
            makeSession: { ChildRulesSession(childId: $0, family: store) },
            makeDailyLimit: { DailyLimitModel(session: $0) }
        )
    }

    func makeSosDetailModel(seed: ActiveSos, emergencyNumber: String) -> SosDetailModel {
        SosDetailModel(seed: seed, child: family.child(seed.childId), emergencyNumber: emergencyNumber, location: locationService)
    }

    var currentEmergencyNumber: String? {
        emergencyNumber()
    }

    func makeHomeModel() -> HomeModel {
        HomeModel(insights: insights, family: family)
    }

    func makeDailySummaryModel(childId: UUID, childName: String) -> DailySummaryModel {
        DailySummaryModel(childId: childId, childName: childName, insights: insights)
    }

    func makeWeeklyModel(childId: UUID) -> WeeklyReportModel {
        WeeklyReportModel(
            childId: childId,
            insights: insights,
            today: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .current
                return LocalDate(Date(), in: calendar)
            }
        )
    }

    func makeAppUsageModel(childId: UUID) -> AppUsageModel {
        AppUsageModel(childId: childId, insights: insights)
    }
}
