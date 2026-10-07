import Foundation
import Testing
import NozirInsights
@testable import NozirAppFeature

private let linkId = UUID(uuidString: "5D0C7E11-2B44-4C1A-8F0E-3A9B6C2D7E10")!
private let linkText = "5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10"
private let aliChildId = UUID(uuidString: "0B0E2A52-6A2F-4D8B-9A55-6F1B2A0C1D01")!

private func row(_ type: NotificationType, link: String?, childId: UUID? = aliChildId, childName: String? = "Ali") -> ParentNotification {
    parentNotification(type: type, childId: childId, childName: childName, deepLink: link)
}

@Suite struct NotificationLinkTests {
    // Spec §4.2 (Android `pushDeepLinkOf`): the backend's five links this app can open.
    @Test func everyLinkThisAppCanOpenIsRead() {
        #expect(NotificationLink.parse("nozir://sos/\(linkText)") == .sos(linkId))
        #expect(NotificationLink.parse("nozir://extra-time/\(linkText)") == .extraTime(linkId))
        #expect(NotificationLink.parse("nozir://protection/\(linkText)") == .protection(linkId))
        #expect(NotificationLink.parse("nozir://summary/\(linkText)") == .summary(linkId))
        #expect(NotificationLink.parse("nozir://app-rules/\(linkText)") == .appRules(linkId))
        #expect(NotificationLink.parse("  nozir://sos/\(linkText.uppercased())/?from=push#top ") == .sos(linkId))
    }

    // Anything unrecognised is `other`: never a guess and never a crash.
    @Test func anythingElseIsOther() {
        let links: [String?] = [
            nil, "", "nozir://", "nozir://notifications", "nozir://map/\(linkText)",
            "nozir://challenges/\(linkText)", "nozir://subscription", "nozir://sos",
            "nozir://sos/not-a-uuid", "nozir://sos/\(linkText)/more", "https://nozir.uz/sos/\(linkText)",
            "nozir://something-new/\(linkText)",
        ]
        for link in links {
            #expect(NotificationLink.parse(link) == .other)
        }
    }

    @Test func aRowOpensTheScreenItsLinkNames() {
        let sos = row(.sosTriggered, link: "nozir://sos/\(linkText)")
        #expect(NotificationLink.step(for: sos) == .sos(ActiveSos(sosId: linkId, childId: aliChildId, childName: "Ali", triggeredAt: notifiedAt)))
        #expect(NotificationLink.step(for: row(.extraTimeRequested, link: "nozir://extra-time/\(linkText)")) == .timeRequest(linkId, usedMinutesToday: nil))
        #expect(NotificationLink.step(for: row(.protectionBroken, link: "nozir://protection/\(linkText)")) == .protection(linkId))
        #expect(NotificationLink.step(for: row(.limitReached, link: "nozir://app-rules/\(linkText)")) == .rules(linkId))
    }

    // D2: DAILY → the child's latest daily summary, WEEKLY → the weekly report.
    @Test func aSummaryLinkOpensByItsType() {
        let link = "nozir://summary/\(linkText)"
        #expect(NotificationLink.step(for: row(.dailySummaryReady, link: link)) == .summary(aliChildId, "Ali"))
        #expect(NotificationLink.step(for: row(.weeklyReportReady, link: link)) == .weekly(aliChildId))
        #expect(NotificationLink.step(for: row(.usageAnomaly, link: link)) == nil)
        // Plan deviation N4: P06 needs the child's name.
        #expect(NotificationLink.step(for: row(.dailySummaryReady, link: link, childName: nil)) == nil)
    }

    // Review Focus 7: a removed child or a family-wide row goes nowhere, and never crashes.
    @Test func aLinkThatNeedsAChildGoesNowhereWithoutOne() {
        #expect(NotificationLink.step(for: row(.sosTriggered, link: "nozir://sos/\(linkText)", childId: nil)) == nil)
        #expect(NotificationLink.step(for: row(.dailySummaryReady, link: "nozir://summary/\(linkText)", childId: nil)) == nil)
        #expect(NotificationLink.step(for: row(.weeklyReportReady, link: "nozir://summary/\(linkText)", childId: nil)) == nil)
        // The ask's own id is enough for P17.
        #expect(NotificationLink.step(for: row(.extraTimeRequested, link: "nozir://extra-time/\(linkText)", childId: nil)) == .timeRequest(linkId, usedMinutesToday: nil))
    }

    @Test func aRowWithoutALinkOrWithAnotherOneGoesNowhere() {
        #expect(NotificationLink.step(for: row(.dailySummaryReady, link: "nozir://notifications", childId: nil)) == nil)
        #expect(NotificationLink.step(for: row(.unknown("TRIAL_ENDING"), link: "nozir://subscription")) == nil)
        #expect(NotificationLink.step(for: row(.safeZoneLeft, link: "nozir://map/\(linkText)")) == nil)
        #expect(NotificationLink.step(for: row(.rulesChanged, link: nil)) == nil)
    }
}
