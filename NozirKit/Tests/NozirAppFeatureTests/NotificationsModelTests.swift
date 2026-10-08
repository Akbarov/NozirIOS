import Foundation
import Testing
import NozirInsights
import NozirNetworking
@testable import NozirAppFeature

private let sosId = UUID(uuidString: "5D0C7E11-2B44-4C1A-8F0E-3A9B6C2D7E10")!
private let first = parentNotification(type: .sosTriggered, tier: .critical)
private let second = parentNotification(type: .limitReached, tier: .action, key: "notification.limit.reached")
private let third = parentNotification(type: .weeklyReportReady, tier: .good, key: "notification.insight.weeklyReady")
private let alreadyRead = parentNotification(type: .rulesChanged, tier: .good, key: "child.rules.changed", readAt: notifiedAt)
/// base64url("1791360000000").
private let cursor = "MTc5MTM2MDAwMDAwMA"

@MainActor
private func setup(_ script: FakeNotifications.Script) -> (NotificationsModel, FakeNotifications) {
    let fake = FakeNotifications(script)
    return (NotificationsModel(service: fake), fake)
}

@MainActor
@Suite struct NotificationsModelTests {
    @Test func theFirstPageAndTheSettingsAreLoaded() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first, second], cursor: cursor))]
        script.preferences = [.success(notificationPreferences())]
        let (model, fake) = setup(script)
        #expect(model.phase == .loading)
        #expect(model.filter == .all)

        await model.appear()

        #expect(model.phase == .ready)
        #expect(model.items == [first, second])
        #expect(model.hasMore)
        #expect(!model.isEmpty)
        #expect(model.preferences == notificationPreferences())
        #expect(model.offlineAfterMinutes == 360)
        #expect(await fake.calls == ["page", "preferences"])
        #expect(await fake.pageAsks == [.init(filter: .all, cursor: nil)])
    }

    @Test func aFirstFailureCanBeRetried() async {
        var script = FakeNotifications.Script()
        script.pages = [.failure(.unexpectedStatus(500)), .success(notificationPage([first]))]
        let (model, _) = setup(script)

        await model.load()
        #expect(model.phase == .failed(.serverProblem))
        #expect(model.items.isEmpty)
        #expect(!model.isEmpty)

        await model.load()
        #expect(model.phase == .ready)
        #expect(model.items == [first])
    }

    // Plan deviation N6: offline over a shown list keeps it and says so.
    @Test(arguments: [offline, ApiFailure.network(code: URLError.Code.timedOut.rawValue)])
    func goingOfflineKeepsTheList(failure: ApiFailure) async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first])), .failure(failure), .success(notificationPage([second, first]))]
        let (model, _) = setup(script)
        await model.load()

        await model.load()
        #expect(model.isOffline)
        #expect(model.items == [first])
        #expect(model.phase == .ready)
        #expect(model.inlineMessage == nil)

        await model.load()
        #expect(!model.isOffline)
        #expect(model.items == [second, first])
    }

    @Test func aServerFaultOverAShownListIsSaidUnderIt() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first])), .failure(.unexpectedStatus(500))]
        let (model, _) = setup(script)
        await model.load()

        await model.load()

        #expect(model.inlineMessage == .serverProblem)
        #expect(!model.isOffline)
        #expect(model.items == [first])
    }

    @Test func noRowsAndNoCursorIsEmpty() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([]))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.isEmpty)
        #expect(!model.hasMore)
    }

    // Review Focus 2: a page whose rows were all unreadable still has a cursor.
    @Test func aPageWithNothingReadableStillOffersMore() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([], cursor: cursor))]
        let (model, _) = setup(script)

        await model.load()

        #expect(!model.isEmpty)
        #expect(model.hasMore)
    }

    @Test func moreRowsAreAppendedWithTheCursor() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first, second], cursor: cursor)), .success(notificationPage([second, third]))]
        let (model, fake) = setup(script)
        await model.load()

        await model.loadMore()

        #expect(model.items == [first, second, third])
        #expect(!model.hasMore)
        #expect(!model.isLoadingMore)
        #expect(await fake.pageAsks == [.init(filter: .all, cursor: nil), .init(filter: .all, cursor: cursor)])
    }

    // Review Focus 2: exactly a full page, then an empty one.
    @Test func anEmptyLastPageEndsTheListWithoutSayingEmpty() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first], cursor: cursor)), .success(notificationPage([]))]
        let (model, _) = setup(script)
        await model.load()

        await model.loadMore()

        #expect(model.items == [first])
        #expect(!model.hasMore)
        #expect(!model.isEmpty)
        #expect(model.inlineMessage == nil)
    }

    // Review Focus 3.
    @Test(.timeLimit(.minutes(5)))
    func twoTapsOnMoreAskOnce() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first], cursor: cursor)), .success(notificationPage([second]))]
        let (model, fake) = setup(script)
        await model.load()
        let gate = PauseGate()
        await fake.add { $0.pageGate = gate }

        let tap = Task { await model.loadMore() }
        await gate.untilPaused()
        #expect(model.isLoadingMore)
        await model.loadMore()
        await gate.release()
        await tap.value

        #expect(await fake.pageAsks.count == 2)
        #expect(model.items == [first, second])
        #expect(!model.isLoadingMore)
    }

    @Test func aFailedMoreIsSaidAndCanBeTriedAgain() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first], cursor: cursor)), .failure(offline), .success(notificationPage([second]))]
        let (model, _) = setup(script)
        await model.load()

        await model.loadMore()
        #expect(model.inlineMessage == .noConnection)
        #expect(model.items == [first])
        #expect(model.hasMore)
        #expect(!model.isLoadingMore)

        await model.loadMore()
        #expect(model.inlineMessage == nil)
        #expect(model.items == [first, second])
    }

    @Test func nothingMoreIsAskedWithoutACursorOrBeforeTheFirstPage() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first]))]
        let (model, fake) = setup(script)

        await model.loadMore()
        await model.load()
        await model.loadMore()

        #expect(await fake.calls == ["page"])
    }

    @Test func aFilterAsksForItsOwnFirstPage() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first, third], cursor: cursor)), .success(notificationPage([first]))]
        let (model, fake) = setup(script)
        await model.load()

        await model.setFilter(.important)

        #expect(model.filter == .important)
        #expect(model.items == [first])
        #expect(!model.hasMore)
        #expect(await fake.pageAsks == [.init(filter: .all, cursor: nil), .init(filter: .important, cursor: nil)])

        await model.setFilter(.important)
        #expect(await fake.pageAsks.count == 2)
    }

    @Test func anEmptyImportantListIsEmpty() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([third])), .success(notificationPage([]))]
        let (model, _) = setup(script)
        await model.load()

        await model.setFilter(.important)

        #expect(model.isEmpty)
        #expect(model.filter == .important)
    }

    // Review Focus 1 (spec §4.2): the older answer never lands over the newer filter.
    @Test(.timeLimit(.minutes(5)))
    func aFilterSwitchDropsTheOlderAnswer() async {
        let gate = PauseGate()
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([third, first], cursor: cursor)), .success(notificationPage([first]))]
        script.pageGate = gate
        let (model, fake) = setup(script)

        let older = Task { await model.load() }
        await gate.untilPaused()
        await model.setFilter(.important)
        await gate.release()
        await older.value

        #expect(model.filter == .important)
        #expect(model.items == [first])
        #expect(!model.hasMore)
        #expect(model.phase == .ready)
        #expect(await fake.pageAsks == [.init(filter: .all, cursor: nil), .init(filter: .important, cursor: nil)])
    }

    // Review Focus 1: a refresh during "Yana" wins; the older rows are not appended.
    @Test(.timeLimit(.minutes(5)))
    func aRefreshDropsALoadMoreInFlight() async {
        var script = FakeNotifications.Script()
        script.pages = [
            .success(notificationPage([first], cursor: cursor)),
            .success(notificationPage([second], cursor: "older")),
            .success(notificationPage([third, first])),
        ]
        let (model, fake) = setup(script)
        await model.load()
        let gate = PauseGate()
        await fake.add { $0.pageGate = gate }

        let more = Task { await model.loadMore() }
        await gate.untilPaused()
        await model.load()
        await gate.release()
        await more.value

        #expect(model.items == [third, first])
        #expect(!model.hasMore)
        #expect(!model.isLoadingMore)
    }

    // Fix round 1: a "Yana" during a refresh would use the old cursor on the new list.
    @Test(.timeLimit(.minutes(5)))
    func moreIsNotAskedWhileTheFirstPageIsLoading() async {
        var script = FakeNotifications.Script()
        script.pages = [
            .success(notificationPage([first], cursor: cursor)),
            .success(notificationPage([third, first], cursor: "newer")),
            .success(notificationPage([second])),
        ]
        let (model, fake) = setup(script)
        await model.load()
        let gate = PauseGate()
        await fake.add { $0.pageGate = gate }

        let refresh = Task { await model.load() }
        await gate.untilPaused()
        await model.loadMore()
        #expect(await fake.pageAsks.count == 2)
        #expect(!model.isLoadingMore)
        await gate.release()
        await refresh.value

        #expect(model.items == [third, first])
        await model.loadMore()
        #expect(await fake.pageAsks.last == .init(filter: .all, cursor: "newer"))
        #expect(model.items == [third, first, second])
    }

    @Test func openingARowMarksItReadAtOnceAndTellsTheServer() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first, second]))]
        script.read = [.success(())]
        let (model, fake) = setup(script)
        await model.load()

        let step = model.open(first)

        #expect(step == nil)
        #expect(model.items[0].isRead)
        #expect(!model.items[1].isRead)
        _ = await model.lastRead?.value
        #expect(await fake.readIds == [first.id])
    }

    // Review Focus 4: a lost connection never un-reads the row or says anything.
    @Test func aFailedReadStaysSilent() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first]))]
        let (model, fake) = setup(script)
        await model.load()

        _ = model.open(first)
        _ = await model.lastRead?.value

        #expect(model.items[0].isRead)
        #expect(model.toast == nil)
        #expect(model.inlineMessage == nil)
        #expect(!model.isOffline)
        #expect(await fake.readIds == [first.id])
    }

    @Test func aRowAlreadyReadIsNotSentAgain() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([alreadyRead]))]
        let (model, fake) = setup(script)
        await model.load()

        _ = model.open(alreadyRead)

        #expect(model.lastRead == nil)
        #expect(await fake.calls == ["page"])
    }

    @Test func openingARowWithALinkGoesThere() async {
        let childId = UUID()
        let sos = parentNotification(childId: childId, deepLink: "nozir://sos/5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10")
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([sos]))]
        script.read = [.success(())]
        let (model, _) = setup(script)
        await model.load()

        let step = model.open(sos)

        #expect(step == .sos(ActiveSos(sosId: sosId, childId: childId, childName: "Ali", triggeredAt: notifiedAt)))
        #expect(model.items[0].isRead)
    }

    // Spec §4.2: no settings, no card — and nothing said; the next visit asks again.
    @Test func settingsThatCannotBeReadHideTheCardQuietly() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first])), .success(notificationPage([first]))]
        script.preferences = [.failure(offline), .success(notificationPreferences())]
        let (model, fake) = setup(script)

        await model.appear()
        #expect(model.preferences == nil)
        #expect(model.offlineAfterMinutes == nil)
        #expect(model.toast == nil)
        #expect(model.phase == .ready)

        await model.appear()
        #expect(model.preferences == notificationPreferences())
        await model.appear()
        #expect(await fake.calls.filter { $0 == "preferences" }.count == 2)
    }

    // Review Focus 5: a full replace with only the threshold changed.
    @Test func theOfflineSettingKeepsEveryOtherField() async {
        var script = FakeNotifications.Script()
        script.preferences = [.success(notificationPreferences())]
        script.save = [.success(notificationPreferences(offlineAfter: 720))]
        let (model, fake) = setup(script)
        await model.loadPreferencesIfNeeded()

        await model.setOfflineAfter(minutes: 720)

        let saved = await fake.saved
        #expect(saved == [notificationPreferences(offlineAfter: 720)])
        #expect(saved.first?.quietHoursStart == "22:00")
        #expect(saved.first?.mutedTypes == ["LIMIT_REACHED", "SOMETHING_NEW"])
        #expect(saved.first?.dailyPushCap == 2)
        #expect(saved.first?.smsForCriticalEnabled == false)
        #expect(model.offlineAfterMinutes == 720)
        #expect(model.pendingOfflineMinutes == nil)
        #expect(model.toast == nil)
    }

    // Review Focus 5: said once; the card shows what is really stored.
    @Test func aRefusedSettingIsSaidAndTheOldValueStays() async {
        var script = FakeNotifications.Script()
        script.preferences = [.success(notificationPreferences())]
        script.save = [.failure(offline)]
        let (model, _) = setup(script)
        await model.loadPreferencesIfNeeded()

        await model.setOfflineAfter(minutes: 1440)

        #expect(model.toast == .noConnection)
        #expect(model.offlineAfterMinutes == 360)
        #expect(model.preferences == notificationPreferences())
        #expect(model.pendingOfflineMinutes == nil)
    }

    @Test func theSameValueOrNoSettingsSendsNothing() async {
        var script = FakeNotifications.Script()
        script.preferences = [.success(notificationPreferences())]
        let (model, fake) = setup(script)

        await model.setOfflineAfter(minutes: 720)
        await model.loadPreferencesIfNeeded()
        await model.setOfflineAfter(minutes: 360)

        #expect(await fake.calls == ["preferences"])
    }

    @Test(.timeLimit(.minutes(5)))
    func aSecondChoiceWhileSavingIsIgnored() async {
        let gate = PauseGate()
        var script = FakeNotifications.Script()
        script.preferences = [.success(notificationPreferences())]
        script.save = [.success(notificationPreferences(offlineAfter: 720))]
        script.saveGate = gate
        let (model, fake) = setup(script)
        await model.loadPreferencesIfNeeded()

        let choice = Task { await model.setOfflineAfter(minutes: 720) }
        await gate.untilPaused()
        #expect(model.offlineAfterMinutes == 720)
        await model.setOfflineAfter(minutes: 1440)
        await gate.release()
        await choice.value

        #expect(await fake.saved.count == 1)
        #expect(model.offlineAfterMinutes == 720)
    }
}
