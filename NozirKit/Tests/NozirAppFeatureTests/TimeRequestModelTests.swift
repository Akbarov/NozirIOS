import Foundation
import Testing
import NozirInsights
import NozirNetworking
@testable import NozirAppFeature

private let askId = UUID()
private let childId = UUID()
private let answeredElsewhere = ApiFailure.server(status: 409, error: ApiError(code: .alreadyDecided))

private func ask(
    kind: ExtraTimeKind = .extraMinutes,
    requested: Int = 30,
    status: ExtraTimeStatus = .pending,
    granted: Int? = nil,
    note: String? = nil
) -> ExtraTimeRequest {
    extraTimeAsk(id: askId, childId: childId, kind: kind, requested: requested, status: status, granted: granted, note: note)
}

@MainActor
private func setup(_ script: FakeExtraTime.Script, used: Int? = 95) -> (TimeRequestModel, FakeExtraTime) {
    let fake = FakeExtraTime(script)
    return (TimeRequestModel(requestId: askId, usedMinutesToday: used, service: fake), fake)
}

@MainActor
@Suite struct TimeRequestModelTests {
    @Test func theAskIsFoundInThePendingList() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([extraTimeAsk(), ask()])]
        let (model, fake) = setup(script)
        #expect(model.phase == .loading)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.request == ask())
        #expect(model.canDecide)
        #expect(model.partialMinutes == 15)
        #expect(model.usedMinutesToday == 95)
        #expect(await fake.calls == ["pending"])
    }

    @Test func anAskNoLongerWaitingIsMissingNotAnError() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([extraTimeAsk()])]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.phase == .missing)
        #expect(model.request == nil)
        #expect(!model.canDecide)
    }

    // Review Focus 5 (T3): an ask the app cannot put into words gets no buttons.
    @Test func anAskOfAnUnknownKindIsMissing() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask(kind: .unknown("SCHOOL_TRIP"))])]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.phase == .missing)
        #expect(!model.canDecide)
    }

    @Test func aFirstFailureCanBeRetried() async {
        var script = FakeExtraTime.Script()
        script.pending = [.failure(.unexpectedStatus(500)), .success([ask()])]
        let (model, _) = setup(script)

        await model.load()
        #expect(model.phase == .failed(.serverProblem))

        await model.load()
        #expect(model.phase == .ready)
    }

    // Spec §6: offline with the ask on screen keeps it, and its buttons.
    @Test func goingOfflineKeepsTheAskOnScreen() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()]), .failure(offline), .success([ask()])]
        let (model, _) = setup(script)
        await model.load()

        await model.load()
        #expect(model.phase == .ready)
        #expect(model.request == ask())
        #expect(model.isOffline)
        #expect(model.canDecide)

        await model.load()
        #expect(!model.isOffline)
    }

    // T5: a server fault over a shown ask is not "offline".
    @Test func aServerFaultOverAShownAskIsSaidNotCalledOffline() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()]), .failure(.unexpectedStatus(500))]
        let (model, _) = setup(script)
        await model.load()

        await model.load()

        #expect(!model.isOffline)
        #expect(model.toast == .serverProblem)
        #expect(model.request == ask())
    }

    @Test func approvingSendsTheWholeAskAndShowsTheAnswer() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        script.decide = [.success(ask(status: .approved, granted: 30))]
        let (model, fake) = setup(script)
        await model.load()

        await model.approve()

        #expect(await fake.decisions == [FakeExtraTime.Decision(id: askId, outcome: .approve, grantedMinutes: nil, note: nil)])
        #expect(model.request?.status == .approved)
        #expect(model.phase == .ready)
        #expect(!model.canDecide)
        #expect(!model.isDeciding)
    }

    @Test(arguments: [(ExtraTimeKind.extraMinutes, 30, 15), (.extraMinutes, 45, 20), (.bedtimeDelay, 30, 15)])
    func thePartialAnswerSendsTheComputedMinutes(kind: ExtraTimeKind, requested: Int, partial: Int) async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask(kind: kind, requested: requested)])]
        script.decide = [.success(ask(kind: kind, requested: requested, status: .approved, granted: partial))]
        let (model, fake) = setup(script)
        await model.load()
        #expect(model.partialMinutes == partial)

        await model.approvePartial()

        #expect(await fake.decisions == [FakeExtraTime.Decision(id: askId, outcome: .partial, grantedMinutes: partial, note: nil)])
        #expect(model.request?.grantedMinutes == partial)
    }

    @Test func withoutASmallerAmountThePartialAnswerSendsNothing() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask(kind: .bedtimeDelay, requested: 15)])]
        let (model, fake) = setup(script)
        await model.load()

        await model.approvePartial()

        #expect(model.partialMinutes == nil)
        #expect(await fake.calls == ["pending"])
    }

    @Test func decliningSendsTheTrimmedNote() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        script.decide = [.success(ask(status: .declined, note: "Ertaga gaplashamiz"))]
        let (model, fake) = setup(script)
        await model.load()

        model.startDecline()
        #expect(model.isWritingDecline)
        model.updateDeclineNote("  Ertaga gaplashamiz \n")
        await model.confirmDecline()

        #expect(await fake.decisions == [FakeExtraTime.Decision(id: askId, outcome: .decline, grantedMinutes: nil, note: "Ertaga gaplashamiz")])
        #expect(!model.isWritingDecline)
        #expect(model.request?.status == .declined)
    }

    // Review Focus 4.
    @Test func aBlankNoteIsNoNoteAndALongOneIsCut() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        script.decide = [.success(ask(status: .declined))]
        let (model, fake) = setup(script)
        await model.load()
        model.startDecline()

        model.updateDeclineNote(String(repeating: "a", count: 300))
        #expect(model.declineNote.count == TimeRequestModel.noteLimit)

        model.updateDeclineNote(" \n ")
        await model.confirmDecline()

        #expect(await fake.decisions == [FakeExtraTime.Decision(id: askId, outcome: .decline, grantedMinutes: nil, note: nil)])
    }

    @Test func goingBackFromTheNoteKeepsWhatWasWrittenAndSendsNothing() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        let (model, fake) = setup(script)
        await model.load()
        model.startDecline()
        model.updateDeclineNote("Ertaga")

        model.cancelDecline()

        #expect(!model.isWritingDecline)
        #expect(model.declineNote == "Ertaga")
        #expect(await fake.calls == ["pending"])
    }

    @Test func confirmingWithoutTheNoteOpenSendsNothing() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        let (model, fake) = setup(script)
        await model.load()

        await model.confirmDecline()

        #expect(await fake.calls == ["pending"])
    }

    // Spec §6: a second tap while the first is in flight does nothing.
    @Test(.timeLimit(.minutes(5)))
    func twoTapsSendOneDecision() async {
        let gate = PauseGate()
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        script.decide = [.success(ask(status: .approved, granted: 30))]
        script.decideGate = gate
        let (model, fake) = setup(script)
        await model.load()

        let first = Task { await model.approve() }
        await gate.untilPaused()
        #expect(model.isDeciding)
        #expect(model.deciding == .approve)
        await model.approve()
        await model.approvePartial()
        model.startDecline()
        #expect(!model.isWritingDecline)

        await gate.release()
        await first.value
        #expect(await fake.decisions.count == 1)
        #expect(model.request?.status == .approved)
        #expect(!model.isDeciding)
    }

    // D6: answered by the other parent, or expired.
    @Test func anAskAnsweredElsewhereSendsTheScreenBackToTheList() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()]), .success([])]
        script.decide = [.failure(answeredElsewhere)]
        let (model, fake) = setup(script)
        await model.load()

        await model.approve()

        #expect(model.phase == .missing)
        #expect(model.request == nil)
        #expect(model.toast == nil)
        #expect(await fake.calls == ["pending", "decide", "pending"])
    }

    @Test func anAskThatIsGoneSendsTheScreenBackToTheList() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()]), .success([])]
        script.decide = [.failure(notFound)]
        let (model, _) = setup(script)
        await model.load()
        model.startDecline()

        await model.confirmDecline()

        #expect(model.phase == .missing)
        #expect(!model.isWritingDecline)
        #expect(model.toast == nil)
    }

    // Review Focus 2: the night is over (409 CONFLICT) — said once, the ask,
    // the open note and the buttons stay, and a second try goes out.
    @Test func aFailedDecisionIsSaidOnceAndCanBeTriedAgain() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask(kind: .bedtimeDelay)])]
        script.decide = [
            .failure(.server(status: 409, error: ApiError(code: .conflict))),
            .success(ask(kind: .bedtimeDelay, status: .declined)),
        ]
        let (model, fake) = setup(script)
        await model.load()
        model.startDecline()
        model.updateDeclineNote("Ertaga")

        await model.confirmDecline()
        #expect(model.toast == .conflict)
        #expect(model.isWritingDecline)
        #expect(model.declineNote == "Ertaga")
        #expect(model.request?.status == .pending)
        #expect(model.canDecide)

        await model.confirmDecline()
        #expect(model.request?.status == .declined)
        #expect(await fake.decisions.count == 2)
    }

    // Review Focus 2 / global constraint: no connection is said, not retried.
    @Test func aDecisionWithNoConnectionIsNotRetried() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        let (model, fake) = setup(script)
        await model.load()

        await model.approve()

        #expect(model.toast == .noConnection)
        #expect(await fake.decisions.count == 1)
        #expect(model.canDecide)
    }

    // Review Focus 1 (T4): the answer stays; the list no longer has it.
    @Test func aRefreshAfterTheAnswerKeepsTheAnswer() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()]), .success([])]
        script.decide = [.success(ask(status: .approved, granted: 30))]
        let (model, fake) = setup(script)
        await model.load()
        await model.approve()

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.request?.status == .approved)
        #expect(await fake.calls == ["pending", "decide"])
    }

    // Spec §6: an older answer never overwrites a newer state.
    @Test(.timeLimit(.minutes(5)))
    func aLateRefreshDoesNotUndoTheAnswer() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        script.decide = [.success(ask(status: .approved, granted: 30))]
        let (model, fake) = setup(script)
        await model.load()
        let gate = PauseGate()
        await fake.add {
            $0.pending = [.success([ask()])]
            $0.pendingGate = gate
        }

        let late = Task { await model.load() }
        await gate.untilPaused()
        await model.approve()
        await gate.release()
        await late.value

        #expect(model.request?.status == .approved)
        #expect(!model.canDecide)
    }

    @Test(.timeLimit(.minutes(5)))
    func anOlderLoadNeverOverwritesANewerOne() async {
        let gate = PauseGate()
        var script = FakeExtraTime.Script()
        script.pending = [.success([]), .success([ask()])]
        script.pendingGate = gate
        let (model, _) = setup(script)

        let older = Task { await model.load() }
        await gate.untilPaused()
        await model.load()
        await gate.release()
        await older.value

        #expect(model.phase == .ready)
        #expect(model.request == ask())
    }
}
