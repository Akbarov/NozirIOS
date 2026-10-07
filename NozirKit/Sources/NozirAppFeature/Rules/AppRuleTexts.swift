import Foundation
import NozirFamily
import NozirL10n

/// P11's words (Android `AppRuleName.kt`, `AppPolicySummary.kt`, `AppRuleMode.kt`).
enum AppRuleTexts {
    /// The phone's label unless it is empty or just the id; then a well-known
    /// name; then the id tidied into words. The package stays the identity.
    static func name(packageId: String, displayName: String?) -> String {
        AppUsageFolding.friendlyName(packageId: packageId, reported: displayName ?? "")
    }

    static func name(_ app: InstalledApp) -> String {
        name(packageId: app.packageId, displayName: app.displayName)
    }

    /// The line under an app's name. A schedule says its hours ("08:00–13:00
    /// yopiq") — a fact a parent can check against a school day. nil for a
    /// mode this app has no words for: "no limit" would be untrue.
    static func summary(_ policy: AppPolicy, _ l10n: L10n) -> String? {
        switch policy.mode {
        case .unrestricted:
            return l10n.appRuleNone
        case .alwaysBlocked:
            return l10n.appRuleAlways
        case .dailyLimit:
            return l10n.appRuleDailyLimit(Durations.short(policy.dailyLimitMinutes ?? 0, l10n))
        case .scheduleBlock:
            guard let window = policy.blockWindows.first else { return l10n.appRuleNone }
            return l10n.appRuleSchedule(window.start.text, window.end.text)
        case .unknown:
            return nil
        }
    }

    /// A rule that shuts the app at some hour is drawn in the accent colour.
    /// A schedule without a window shuts nothing (it reads "Cheklov yo'q").
    static func closesTheApp(_ policy: AppPolicy) -> Bool {
        switch policy.mode {
        case .alwaysBlocked: return true
        case .scheduleBlock: return !policy.blockWindows.isEmpty
        default: return false
        }
    }

    /// P09's "Ilovalar" row. A saved "no limit" is a row, not a rule.
    static func hubRow(_ policies: [AppPolicy], _ l10n: L10n) -> String {
        let count = policies.filter { $0.mode != .unrestricted }.count
        return count == 0 ? l10n.rulesLinkAppsNone : l10n.rulesLinkAppsCount(count)
    }

    /// An unknown mode never shows the server's raw name: it reads as "no limit".
    static func modeLabel(_ mode: AppPolicyMode, _ l10n: L10n) -> String {
        switch mode {
        case .unrestricted: return l10n.appRuleModeNone
        case .dailyLimit: return l10n.appRuleModeDailyLimit
        case .scheduleBlock: return l10n.appRuleModeSchedule
        case .alwaysBlocked: return l10n.appRuleAlways
        case .unknown: return l10n.appRuleNone
        }
    }
}

/// Finding one app among fifty by part of its name (Android `AppSearch.kt`):
/// substring, on the name shown, the name the phone gave and the package id.
enum AppSearch {
    /// Straight, curly, both Uzbek modifier letters and the backtick: almost
    /// nobody types the one the label uses.
    private static let apostrophes: Set<Unicode.Scalar> = ["'", "\u{2018}", "\u{2019}", "\u{02BB}", "\u{02BC}", "`"]

    /// Trimmed, lower-cased (`lowercased()` is locale-independent, so a
    /// Turkish phone still finds "Instagram"), apostrophes folded to `'`.
    static func key(_ text: String) -> String {
        var folded = String.UnicodeScalarView()
        for scalar in text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().unicodeScalars {
            folded.append(apostrophes.contains(scalar) ? "'" : scalar)
        }
        return String(folded)
    }

    /// Nothing typed is everything, in the server's order.
    static func matching(_ apps: [InstalledApp], _ query: String) -> [InstalledApp] {
        let needle = key(query)
        guard !needle.isEmpty else { return apps }
        return apps.filter { app in
            key(AppRuleTexts.name(app)).contains(needle)
                || key(app.displayName ?? "").contains(needle)
                || key(app.packageId).contains(needle)
        }
    }
}
