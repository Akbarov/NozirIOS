import Foundation
import Testing
import NozirDesignSystem
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

@Suite struct ProtectionTextsTests {
    private let l10n = L10n(.uz)

    // Spec §5.1 and D2: the Home row's words and card follow the level.
    @Test func theHomeRowFollowsTheLevel() {
        #expect(ProtectionTexts.homeTitle(.healthy, l10n) == l10n.homeProtectionHealthyTitle)
        #expect(ProtectionTexts.homeBody(.healthy, l10n) == l10n.homeProtectionHealthyBody)
        #expect(ProtectionTexts.homeTitle(.degraded, l10n) == l10n.homeProtectionDegradedTitle)
        #expect(ProtectionTexts.homeBody(.degraded, l10n) == l10n.homeProtectionDegradedBody)
        #expect(ProtectionTexts.homeTitle(.broken, l10n) == l10n.homeProtectionBrokenTitle)
        #expect(ProtectionTexts.homeBody(.broken, l10n) == l10n.homeProtectionBrokenBody)
        #expect(ProtectionTexts.cardTone(.healthy) == .plain)
        #expect(ProtectionTexts.cardTone(.degraded) == .attention)
        #expect(ProtectionTexts.cardTone(.broken) == .critical)
    }

    @Test func theSummaryCountsEveryPermissionNotGranted() {
        let mixed = protectionStatus(permissions: [
            protectionPermission(.usageAccess, .granted),
            protectionPermission(.overlay, .denied),
            protectionPermission(.battery, .skipped),
            protectionPermission(.oemAutostart, revoked: true),
        ])

        #expect(ProtectionTexts.levelTitle(.healthy, l10n) == l10n.protectionLevelHealthyTitle)
        #expect(ProtectionTexts.levelTitle(.degraded, l10n) == l10n.protectionLevelDegradedTitle)
        #expect(ProtectionTexts.levelTitle(.broken, l10n) == l10n.protectionLevelBrokenTitle)
        #expect(ProtectionTexts.summaryBody(mixed, l10n) == l10n.protectionBodyNeedsFixing(3))
        #expect(ProtectionTexts.summaryBody(protectionStatus(permissions: [protectionPermission(.overlay, .granted)]), l10n) == l10n.protectionBodyAllWorking)
        #expect(ProtectionTexts.summaryBody(protectionStatus(permissions: []), l10n) == l10n.protectionBodyAllWorking)
    }

    @Test func everyKindHasItsName() {
        #expect(ProtectionTexts.name(.usageAccess, l10n) == l10n.protectionPermissionUsageAccess)
        #expect(ProtectionTexts.name(.overlay, l10n) == l10n.protectionPermissionOverlay)
        #expect(ProtectionTexts.name(.notifications, l10n) == l10n.protectionPermissionNotifications)
        #expect(ProtectionTexts.name(.location, l10n) == l10n.protectionPermissionLocation)
        #expect(ProtectionTexts.name(.battery, l10n) == l10n.protectionPermissionBattery)
        #expect(ProtectionTexts.name(.oemAutostart, l10n) == l10n.protectionPermissionAutostart)
        #expect(Set(PermissionKind.allCases.map { ProtectionTexts.name($0, l10n) }).count == 6)
    }

    // Spec §4.2 (Android PermissionStateLabel / PermissionDisplayLevel): granted
    // works; a revoked one switched itself off (it wins over skipped); skipped
    // was passed over; anything else was never turned on. Never critical.
    @Test func theStateWordAndDotFollowAndroid() {
        let granted = protectionPermission(.overlay, .granted)
        let revoked = protectionPermission(.overlay, .denied, revoked: true)
        let revokedSkipped = protectionPermission(.overlay, .skipped, revoked: true)
        let skipped = protectionPermission(.overlay, .skipped)
        let denied = protectionPermission(.overlay, .denied)

        #expect(ProtectionTexts.stateLabel(granted, l10n) == l10n.protectionStateGranted)
        #expect(ProtectionTexts.stateNote(granted, l10n) == nil)
        #expect(ProtectionTexts.stateLine(granted, l10n) == l10n.protectionStateGranted)
        #expect(ProtectionTexts.dotLevel(granted) == .good)

        #expect(ProtectionTexts.stateLine(revoked, l10n) == l10n.protectionStateWithNote(l10n.protectionStateRevoked, l10n.protectionNoteRevoked))
        #expect(ProtectionTexts.stateLine(revokedSkipped, l10n) == ProtectionTexts.stateLine(revoked, l10n))
        #expect(ProtectionTexts.dotLevel(revoked) == .action)

        #expect(ProtectionTexts.stateLine(skipped, l10n) == l10n.protectionStateWithNote(l10n.protectionStateSkipped, l10n.protectionNoteSkipped))
        #expect(ProtectionTexts.dotLevel(skipped) == .attention)

        #expect(ProtectionTexts.stateLine(denied, l10n) == l10n.protectionStateWithNote(l10n.protectionStateDenied, l10n.protectionNoteDenied))
        #expect(ProtectionTexts.dotLevel(denied) == .attention)
    }

    // Review Focus 1 and P6: how long the phone has been quiet, or that it never spoke.
    @Test func theStaleNoteSaysHowLongOrNever() {
        let now = lastReport.addingTimeInterval(40 * 3_600)

        #expect(ProtectionTexts.staleNote(protectionStatus(isStale: false), now: now, l10n) == nil)
        #expect(ProtectionTexts.staleNote(protectionStatus(lastReportAt: nil, isStale: true), now: now, l10n) == l10n.protectionStaleNoteNever)
        #expect(ProtectionTexts.staleNote(protectionStatus(isStale: true), now: now, l10n) == l10n.protectionStaleNote(l10n.elapsedStaleHours(40)))
        #expect(ProtectionTexts.staleNote(protectionStatus(isStale: true), now: lastReport.addingTimeInterval(2 * 3_600), l10n) == l10n.protectionStaleNote(l10n.elapsedHours(2)))
    }

    // Spec §4.2: the 11 served keys, and the generic steps for anything else.
    @Test func everyServedKeyHasItsSteps() {
        let served: [(String, String)] = [
            ("oem.xiaomi.autostart", l10n.oemXiaomiAutostart),
            ("oem.oppo.autostart", l10n.oemOppoAutostart),
            ("oem.vivo.autostart", l10n.oemVivoAutostart),
            ("oem.realme.autostart", l10n.oemRealmeAutostart),
            ("oem.infinix.autostart", l10n.oemInfinixAutostart),
            ("oem.generic.autostart", l10n.oemGenericAutostart),
            ("oem.xiaomi.battery", l10n.oemXiaomiBattery),
            ("oem.samsung.battery", l10n.oemSamsungBattery),
            ("oem.generic.battery", l10n.oemGenericBattery),
            ("oem.generic.usage", l10n.oemGenericUsage),
            ("oem.generic.overlay", l10n.oemGenericOverlay),
        ]
        for (key, steps) in served {
            #expect(ProtectionTexts.steps(key, l10n) == steps)
        }
        // Android words some phones' steps identically (Xiaomi, Realme and Infinix autostart in uz),
        // so the texts cannot be told apart by value; each key must still be a real served step.
        #expect(Set(served.map(\.0)).count == 11)
        #expect(served.allSatisfy { $0.1 != l10n.protectionInstructionUnknown })
        #expect(ProtectionTexts.steps("oem.huawei.autostart", l10n) == l10n.protectionInstructionUnknown)
        #expect(ProtectionTexts.steps(nil, l10n) == l10n.protectionInstructionUnknown)
    }

    // D3: one card, for the first permission not granted; its own key wins over the status's.
    @Test func theInstructionIsForTheFirstBrokenPermission() {
        let status = protectionStatus(
            permissions: [
                protectionPermission(.usageAccess, .granted, key: "oem.generic.usage"),
                protectionPermission(.battery, key: "oem.xiaomi.battery"),
                protectionPermission(.oemAutostart, key: "oem.xiaomi.autostart"),
            ],
            instructionKey: "oem.generic.overlay"
        )
        let noOwnKey = protectionStatus(permissions: [protectionPermission(.overlay)], manufacturer: "samsung", instructionKey: "oem.generic.overlay")

        #expect(ProtectionTexts.instruction(status, childName: "Ali", l10n) == l10n.protectionInstructionLine("Ali", "Xiaomi", l10n.oemXiaomiBattery))
        #expect(ProtectionTexts.instruction(noOwnKey, childName: nil, l10n) == l10n.protectionInstructionLineUnnamed("Samsung", l10n.oemGenericOverlay))
        #expect(ProtectionTexts.instruction(noOwnKey, childName: "  ", l10n) == l10n.protectionInstructionLineUnnamed("Samsung", l10n.oemGenericOverlay))
        #expect(ProtectionTexts.instruction(protectionStatus(permissions: [protectionPermission(.overlay, .granted)]), childName: "Ali", l10n) == nil)
    }

    @Test func thePhoneIsTheMakeWithACapital() {
        #expect(ProtectionTexts.phone("xiaomi") == "Xiaomi")
        #expect(ProtectionTexts.phone("Samsung") == "Samsung")
        #expect(ProtectionTexts.phone("") == "")
    }

    @Test func theSendButtonNamesTheChild() {
        #expect(ProtectionTexts.sendTitle(childName: "Ali", l10n) == l10n.protectionActionSend("Ali"))
        #expect(ProtectionTexts.sendTitle(childName: nil, l10n) == l10n.protectionActionSendUnnamed)
        #expect(ProtectionTexts.sendTitle(childName: " ", l10n) == l10n.protectionActionSendUnnamed)
    }
}
