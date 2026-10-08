import Foundation
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P18 and its Home row in words and tones (Android `ProtectionRow`,
/// `ProtectionSummaryCard`, `PermissionKindLabel`, `PermissionStateLabel`,
/// `PermissionDisplayLevel`, `ProtectionStaleNotice`, `OemInstructionTextRes`,
/// `OemInstructionCard`, `ProtectionFix`). A blank child name reads as "the child".
enum ProtectionTexts {
    // MARK: Home row and summary card

    static func homeTitle(_ level: ProtectionLevel, _ l10n: L10n) -> String {
        switch level {
        case .healthy: l10n.homeProtectionHealthyTitle
        case .degraded: l10n.homeProtectionDegradedTitle
        case .broken: l10n.homeProtectionBrokenTitle
        }
    }

    static func homeBody(_ level: ProtectionLevel, _ l10n: L10n) -> String {
        switch level {
        case .healthy: l10n.homeProtectionHealthyBody
        case .degraded: l10n.homeProtectionDegradedBody
        case .broken: l10n.homeProtectionBrokenBody
        }
    }

    /// Spec D2, for the Home row and the summary card only.
    static func cardTone(_ level: ProtectionLevel) -> NozirCardTone {
        switch level {
        case .healthy: .plain
        case .degraded: .attention
        case .broken: .critical
        }
    }

    static func levelTitle(_ level: ProtectionLevel, _ l10n: L10n) -> String {
        switch level {
        case .healthy: l10n.protectionLevelHealthyTitle
        case .degraded: l10n.protectionLevelDegradedTitle
        case .broken: l10n.protectionLevelBrokenTitle
        }
    }

    /// "Barcha ruxsatlar ishlayapti" or "N ta sozlama tuzatilishi kerak"; N counts every permission not granted.
    static func summaryBody(_ status: ProtectionStatus, _ l10n: L10n) -> String {
        let count = status.kindsToFix.count
        return count == 0 ? l10n.protectionBodyAllWorking : l10n.protectionBodyNeedsFixing(count)
    }

    // MARK: Permission rows

    static func name(_ kind: PermissionKind, _ l10n: L10n) -> String {
        switch kind {
        case .usageAccess: l10n.protectionPermissionUsageAccess
        case .overlay: l10n.protectionPermissionOverlay
        case .notifications: l10n.protectionPermissionNotifications
        case .location: l10n.protectionPermissionLocation
        case .battery: l10n.protectionPermissionBattery
        case .oemAutostart: l10n.protectionPermissionAutostart
        }
    }

    /// The word that travels with the colour, so the colour is never alone.
    static func stateLabel(_ permission: ProtectionPermission, _ l10n: L10n) -> String {
        if permission.status == .granted { return l10n.protectionStateGranted }
        if permission.wasRevoked { return l10n.protectionStateRevoked }
        return permission.status == .skipped ? l10n.protectionStateSkipped : l10n.protectionStateDenied
    }

    /// Why it is in that state; nil when it works.
    static func stateNote(_ permission: ProtectionPermission, _ l10n: L10n) -> String? {
        if permission.status == .granted { return nil }
        if permission.wasRevoked { return l10n.protectionNoteRevoked }
        return permission.status == .skipped ? l10n.protectionNoteSkipped : l10n.protectionNoteDenied
    }

    /// "Oʻchib qolgan · Telefon yangilangandan keyin oʻchib qolgan", or just "Ishlayapti".
    static func stateLine(_ permission: ProtectionPermission, _ l10n: L10n) -> String {
        let label = stateLabel(permission, l10n)
        return stateNote(permission, l10n).map { l10n.protectionStateWithNote(label, $0) } ?? label
    }

    /// One that broke by itself outranks one never granted; red is kept for SOS.
    static func dotLevel(_ permission: ProtectionPermission) -> NozirStatusLevel {
        if permission.status == .granted { return .good }
        return permission.wasRevoked ? .action : .attention
    }

    // MARK: Stale note

    /// Nil while the phone reports; otherwise how long it has been quiet, or that it never spoke.
    static func staleNote(_ status: ProtectionStatus, now: Date, _ l10n: L10n) -> String? {
        guard status.isStale else { return nil }
        guard let at = status.lastReportAt else { return l10n.protectionStaleNoteNever }
        return l10n.protectionStaleNote(ElapsedTime(from: at, to: now).text(l10n))
    }

    // MARK: The fix

    /// The steps a served key stands for; a key this release has never heard of gets the generic steps.
    static func steps(_ key: String?, _ l10n: L10n) -> String {
        switch key ?? "" {
        case "oem.xiaomi.autostart": l10n.oemXiaomiAutostart
        case "oem.xiaomi.battery": l10n.oemXiaomiBattery
        case "oem.oppo.autostart": l10n.oemOppoAutostart
        case "oem.vivo.autostart": l10n.oemVivoAutostart
        case "oem.samsung.battery": l10n.oemSamsungBattery
        case "oem.realme.autostart": l10n.oemRealmeAutostart
        case "oem.infinix.autostart": l10n.oemInfinixAutostart
        case "oem.generic.autostart": l10n.oemGenericAutostart
        case "oem.generic.usage": l10n.oemGenericUsage
        case "oem.generic.overlay": l10n.oemGenericOverlay
        case "oem.generic.battery": l10n.oemGenericBattery
        default: l10n.protectionInstructionUnknown
        }
    }

    /// "xiaomi" → "Xiaomi" (Android `replaceFirstChar { it.uppercase() }`).
    static func phone(_ manufacturer: String) -> String {
        manufacturer.prefix(1).uppercased() + String(manufacturer.dropFirst())
    }

    /// "Ali telefonida (Xiaomi): …" for the first permission not granted; nil when all work.
    static func instruction(_ status: ProtectionStatus, childName: String?, _ l10n: L10n) -> String? {
        guard let first = status.permissions.first(where: \.needsFixing) else { return nil }
        let text = steps(first.instructionKey ?? status.instructionKey, l10n)
        let device = phone(status.manufacturer)
        return LocationTexts.present(childName).map { l10n.protectionInstructionLine($0, device, text) }
            ?? l10n.protectionInstructionLineUnnamed(device, text)
    }

    static func sendTitle(childName: String?, _ l10n: L10n) -> String {
        LocationTexts.present(childName).map { l10n.protectionActionSend($0) } ?? l10n.protectionActionSendUnnamed
    }
}
