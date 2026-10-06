import Foundation
import Observation
import NozirFamily
import NozirInsights

/// The app P11 opens the editor on, and the phone's name for it (sent with the save).
struct AppRuleTarget: Hashable, Sendable {
    let packageId: String
    let displayName: String?
}

/// P11 (Android `AppRulesViewModel`): the rules the session holds, and the
/// apps on the child's phone a rule could still be written for. One app's
/// edit is `AppRuleModel`'s, on a screen of its own (spec D1).
@MainActor
@Observable
final class AppRulesModel {
    let session: ChildRulesSession
    /// The phone's list; nil until it has been read.
    private(set) var installedApps: [InstalledApp]?
    private(set) var isLoadingApps = false
    /// The first read of the phone's list failed. Said, with Retry (spec D3):
    /// a silent empty picker reads as "the child has no apps".
    private(set) var appsLoadFailure: UserMessage?
    private(set) var isChoosingApp = false
    private(set) var query = ""

    init(session: ChildRulesSession) {
        self.session = session
    }

    /// In the server's order. A saved "no limit" stays a row: there is no delete.
    var policies: [AppPolicy] {
        session.snapshot?.appPolicies ?? []
    }

    /// The phone's apps a rule could be written for, in the server's order.
    var addableApps: [InstalledApp] {
        (installedApps ?? []).filter { isAddable($0) }
    }

    var shownApps: [InstalledApp] {
        AppSearch.matching(addableApps, query)
    }

    /// Not one with a rule (a "no limit" one included), not one the server
    /// never lets a rule touch, and not the usage screens' "others" bucket.
    func isAddable(_ app: InstalledApp) -> Bool {
        guard let snapshot = session.snapshot else { return false }
        return app.packageId != AppUsageEntry.otherAppsPackageId
            && !snapshot.neverBlockedPackages.contains(app.packageId)
            && !snapshot.appPolicies.contains { $0.packageId == app.packageId }
    }

    func name(of policy: AppPolicy) -> String {
        AppRuleTexts.name(packageId: policy.packageId, displayName: displayName(of: policy))
    }

    /// The session once, then the phone's list once: a tab switch keeps both
    /// and the picker as it was.
    func load() async {
        await session.load()
        guard session.snapshot != nil, installedApps == nil else { return }
        await loadApps()
    }

    func retryApps() async {
        await loadApps()
    }

    /// Pull to refresh. Nothing while a save of the hub is on its way: a newer
    /// version read mid-save would be the one that save is checked against.
    func refresh() async {
        guard !session.isWriting else { return }
        await session.reload()
        await loadApps()
    }

    /// Opening and closing both start from nothing typed: a query kept across
    /// a close greets the next opening with a list that looks empty.
    func toggleChoosing() {
        isChoosingApp.toggle()
        query = ""
    }

    func setQuery(_ text: String) {
        query = text
    }

    /// nil for an app no rule may be written for (the server would refuse it).
    func choose(_ app: InstalledApp) -> AppRuleTarget? {
        guard isAddable(app) else { return nil }
        isChoosingApp = false
        query = ""
        return AppRuleTarget(packageId: app.packageId, displayName: app.displayName)
    }

    func open(_ policy: AppPolicy) -> AppRuleTarget {
        AppRuleTarget(packageId: policy.packageId, displayName: displayName(of: policy))
    }

    /// The phone's current name first, then the one saved with the rule.
    private func displayName(of policy: AppPolicy) -> String? {
        installedApps?.first { $0.packageId == policy.packageId }?.displayName ?? policy.displayName
    }

    /// A later read that fails leaves a shown list alone (Android does the same).
    private func loadApps() async {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        if installedApps == nil { appsLoadFailure = nil }
        defer { isLoadingApps = false }
        do {
            installedApps = try await session.family.service.installedApps(of: session.childId)
            appsLoadFailure = nil
        } catch is CancellationError {
            return
        } catch {
            if installedApps == nil { appsLoadFailure = UserMessage(error) }
        }
    }
}
