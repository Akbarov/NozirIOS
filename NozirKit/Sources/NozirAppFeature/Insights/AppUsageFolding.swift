import Foundation
import NozirInsights

/// Android `FoldedToTopApps.kt` and `FriendlyAppName.kt`.
enum AppUsageFolding {
    /// There are four series colours; everything past them is one grey bucket.
    static let keptApps = 4

    /// The four longest-used apps (ties keep the server's order), then one
    /// "others" entry holding the rest and any bucket the server already made.
    /// The bucket is always last: it is not an app and is not compared with one.
    static func folded(_ entries: [AppUsageEntry]) -> [AppUsageEntry] {
        let apps = entries.enumerated()
            .filter { !$0.element.isOtherApps }
            .sorted { lhs, rhs in
                lhs.element.minutes != rhs.element.minutes
                    ? lhs.element.minutes > rhs.element.minutes
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
        let kept = Array(apps.prefix(keptApps))
        let buckets = entries.filter(\.isOtherApps)
        let foldedMinutes = apps.dropFirst(keptApps).reduce(0) { $0 + $1.minutes }
            + buckets.reduce(0) { $0 + $1.minutes }
        guard foldedMinutes > 0 else { return kept }
        let others = AppUsageEntry(
            packageId: AppUsageEntry.otherAppsPackageId,
            displayName: buckets.first?.displayName ?? "",
            minutes: foldedMinutes
        )
        return kept + [others]
    }

    /// `minutes × 100 / total`, whole percent; a zero total is 0%.
    static func sharePercent(_ minutes: Int, of total: Int) -> Int {
        total > 0 ? minutes * 100 / total : 0
    }

    /// The label the child's phone reported, unless it is just the id; then a
    /// short list of well-known apps; then the id tidied into words.
    static func friendlyName(packageId: String, reported: String) -> String {
        let trimmed = reported.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != packageId { return trimmed }
        if let known = wellKnown[packageId] { return known }
        return tidied(packageId)
    }

    private static func tidied(_ packageId: String) -> String {
        let segments = packageId.split(separator: ".").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let chosen = segments.last(where: { !uninformative.contains($0.lowercased()) }) ?? segments.last else {
            return packageId
        }
        let words = chosen.split(whereSeparator: { $0 == "_" || $0 == "-" }).filter { !$0.isEmpty }
        let name = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return name.isEmpty ? packageId : name
    }

    private static let uninformative: Set<String> = [
        "com", "org", "net", "io", "co", "me", "app", "apps", "android",
        "mobile", "client", "free", "lite", "pro", "plus", "main", "release",
    ]

    private static let wellKnown: [String: String] = [
        "com.google.android.youtube": "YouTube",
        "com.google.android.apps.youtube.kids": "YouTube Kids",
        "com.google.android.apps.youtube.music": "YouTube Music",
        "com.google.android.gm": "Gmail",
        "com.google.android.apps.photos": "Google Photos",
        "com.google.android.googlequicksearchbox": "Google",
        "com.android.vending": "Play Store",
        "com.android.chrome": "Chrome",
        "com.whatsapp": "WhatsApp",
        "org.telegram.messenger": "Telegram",
        "com.instagram.android": "Instagram",
        "com.facebook.katana": "Facebook",
        "com.facebook.orca": "Messenger",
        "com.zhiliaoapp.musically": "TikTok",
        "com.snapchat.android": "Snapchat",
        "com.twitter.android": "X",
        "com.viber.voip": "Viber",
        "com.imo.android.imoim": "imo",
        "com.vkontakte.android": "VK",
        "ru.ok.android": "Odnoklassniki",
        "com.discord": "Discord",
        "com.spotify.music": "Spotify",
        "com.netflix.mediaclient": "Netflix",
        "com.pinterest": "Pinterest",
        "com.linkedin.android": "LinkedIn",
        "com.duolingo": "Duolingo",
        "com.yandex.browser": "Yandex Browser",
        "com.opera.mini.native": "Opera Mini",
        "com.UCMobile.intl": "UC Browser",
        "com.roblox.client": "Roblox",
        "com.mojang.minecraftpe": "Minecraft",
        "com.supercell.brawlstars": "Brawl Stars",
        "com.supercell.clashofclans": "Clash of Clans",
        "com.dts.freefireth": "Free Fire",
        "com.tencent.ig": "PUBG Mobile",
        "com.activision.callofduty.shooter": "Call of Duty Mobile",
    ]
}
