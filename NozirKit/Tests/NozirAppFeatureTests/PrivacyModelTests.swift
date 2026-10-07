import Foundation
import Testing
import NozirFamily
import NozirL10n
import NozirNetworking
import NozirPrivacy
@testable import NozirAppFeature

@MainActor
private final class SignOutSpy {
    private(set) var count = 0

    func signOut() {
        count += 1
    }
}

private let owner = ParentProfile(displayName: "Zohid", phoneE164: nil, locale: "uz", role: "OWNER")
private let guardian = ParentProfile(displayName: "Malika", phoneE164: nil, locale: "uz", role: "GUARDIAN")
private let forbidden = ApiFailure.server(status: 403, error: ApiError(code: .forbidden))

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// `times` loads' worth of answers: the list, and the current request.
private func loaded(current: Result<ErasureRequestStatus?, ApiFailure> = .success(nil), times: Int = 1) -> FakePrivacy.Script {
    var script = FakePrivacy.Script()
    script.disclosure = Array(repeating: .success(sampleDisclosure), count: times)
    script.current = Array(repeating: current, count: times)
    return script
}

@MainActor
private func setup(
    _ script: FakePrivacy.Script,
    parents: [Result<ParentProfile, ApiFailure>] = [.success(owner)],
    children: [Child] = [],
    config: PrivacyConfig = PrivacyConfig(deletionDelayDays: 7, policyURL: nil)
) async -> (PrivacyModel, FakePrivacy, SignOutSpy) {
    var familyScript = FakeFamily.Script()
    familyScript.me = parents
    familyScript.children = [.success(children)]
    let family = FamilyStore(service: FakeFamily(familyScript))
    try? await family.refresh()
    let fake = FakePrivacy(script)
    let spy = SignOutSpy()
    let model = PrivacyModel(privacy: fake, family: family, config: config, calendar: utc, onSignedOut: { spy.signOut() })
    return (model, fake, spy)
}

@MainActor
@Suite struct PrivacyModelTests {
    private let l10n = L10n(.uz)

    @Test func anOwnerSeesTheServersListAndTheButton() async {
        let (model, fake, _) = await setup(loaded())

        await model.load()

        #expect(model.disclosure == sampleDisclosure)
        #expect(model.loadFailure == nil)
        #expect(!model.isOffline)
        #expect(model.deletion == .idle)
        #expect(model.isOwner)
        #expect(model.canRequestDeletion)
        #expect(await fake.calls.sorted() == ["current", "disclosure"])
    }

    @Test func aPendingRequestShowsItsDateAndNoButton() async {
        let (model, _, _) = await setup(loaded(current: .success(pendingRequest)))

        await model.load()

        #expect(model.deletion == .requested(executableAt: deletionDate))
        #expect(!model.canRequestDeletion)
        #expect(model.requestedBody(deletionDate, l10n) == l10n.privacyDeleteRequestedBody("14-oktabr 2026"))
        #expect(model.requestedBody(deletionDate, L10n(.en)) == L10n(.en).privacyDeleteRequestedBody("October 14, 2026"))
    }

    @Test func aRequestThatCannotBeReadHidesTheSection() async {
        let (model, _, _) = await setup(loaded(current: .failure(offline)))

        await model.load()

        #expect(model.disclosure == sampleDisclosure)
        #expect(model.deletion == .unknown)
        #expect(!model.canRequestDeletion)
    }

    @Test func aListThatCannotBeLoadedCanBeRetried() async {
        var script = FakePrivacy.Script()
        script.disclosure = [.failure(offline), .success(sampleDisclosure)]
        script.current = [.success(nil), .success(nil)]
        let (model, _, _) = await setup(script, parents: [.success(owner), .success(owner)])

        await model.load()
        #expect(model.disclosure == nil)
        #expect(model.loadFailure == .noConnection)

        await model.load()
        #expect(model.disclosure == sampleDisclosure)
        #expect(model.loadFailure == nil)
        #expect(!model.isOffline)
    }

    @Test func aLostConnectionKeepsTheListWithANote() async {
        var script = FakePrivacy.Script()
        script.disclosure = [
            .success(sampleDisclosure),
            .failure(offline),
            .failure(.server(status: 500, error: ApiError(code: .internalError))),
        ]
        script.current = [.success(nil), .success(nil), .success(nil)]
        let (model, _, _) = await setup(script, parents: [.success(owner), .success(owner), .success(owner)])
        await model.load()

        await model.load()
        #expect(model.disclosure == sampleDisclosure)
        #expect(model.isOffline)
        #expect(model.loadFailure == nil)

        // Only a lost connection earns the offline note.
        await model.load()
        #expect(model.disclosure == sampleDisclosure)
        #expect(!model.isOffline)
    }

    @Test func anEmptyListIsAnAnswerNotAFault() async {
        var script = FakePrivacy.Script()
        script.disclosure = [.success(PrivacyDisclosure(documentVersion: "", locale: "uz", seen: [], notSeen: []))]
        script.current = [.success(nil)]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.disclosure?.isEmpty == true)
        #expect(model.loadFailure == nil)
    }

    @Test func aGuardianSeesNoButtonButSeesTheRequest() async {
        let (model, fake, _) = await setup(loaded(), parents: [.success(guardian)])
        await model.load()

        #expect(!model.isOwner)
        #expect(model.deletion == .idle)
        #expect(!model.canRequestDeletion)
        model.startDelete()
        await model.confirmDelete()
        #expect(model.deletion == .idle)
        #expect(await fake.calls.filter { $0 == "request" }.isEmpty)

        let (pending, _, _) = await setup(loaded(current: .success(pendingRequest)), parents: [.success(guardian)])
        await pending.load()
        #expect(pending.deletion == .requested(executableAt: deletionDate))
    }

    // Review Focus 4: an unread role is not an owner.
    @Test func anUnreadableRoleOffersNoButtonButShowsTheRequest() async {
        let (model, _, _) = await setup(loaded(), parents: [.failure(offline)])
        await model.load()

        #expect(!model.isOwner)
        #expect(model.deletion == .idle)
        #expect(!model.canRequestDeletion)

        let (pending, _, _) = await setup(loaded(current: .success(pendingRequest)), parents: [.failure(offline)])
        await pending.load()
        #expect(pending.deletion == .requested(executableAt: deletionDate))
    }

    @Test func askConfirmDoneEndsTheSession() async {
        var script = loaded()
        script.request = [.success(recordedRequest)]
        let (model, fake, spy) = await setup(script)
        await model.load()

        model.startDelete()
        #expect(model.deletion == .confirming)
        model.cancelDelete()
        #expect(model.deletion == .idle)
        #expect(await fake.calls.filter { $0 == "request" }.isEmpty)

        model.startDelete()
        await model.confirmDelete()

        #expect(model.deletion == .requested(executableAt: deletionDate))
        #expect(model.toast == nil)
        #expect(spy.count == 1)
        #expect(await fake.calls.filter { $0 == "request" }.count == 1)
    }

    @Test func nothingIsSentWithoutTheConfirmation() async {
        var script = loaded()
        script.request = [.success(recordedRequest)]
        let (model, fake, spy) = await setup(script)
        await model.load()

        await model.confirmDelete()

        #expect(model.deletion == .idle)
        #expect(spy.count == 0)
        #expect(await fake.calls.filter { $0 == "request" }.isEmpty)
    }

    @Test(.timeLimit(.minutes(5)))
    func twoTapsRequestOnce() async {
        let gate = PauseGate()
        var script = loaded()
        script.request = [.success(recordedRequest)]
        script.requestGate = gate
        let (model, fake, spy) = await setup(script)
        await model.load()
        model.startDelete()

        let first = Task { await model.confirmDelete() }
        await gate.untilPaused()
        #expect(model.deletion == .submitting)
        await model.confirmDelete()
        #expect(await fake.calls.filter { $0 == "request" }.count == 1)

        await gate.release()
        await first.value
        #expect(spy.count == 1)
        #expect(await fake.calls.filter { $0 == "request" }.count == 1)
    }

    @Test func aRefusalSaysSoAndGoesBackToTheButton() async {
        var script = loaded()
        script.request = [.failure(forbidden)]
        let (model, _, spy) = await setup(script)
        await model.load()
        model.startDelete()

        await model.confirmDelete()

        #expect(model.toast == .permissionDenied)
        #expect(model.deletion == .idle)
        #expect(spy.count == 0)
    }

    @Test func aRequestThatDidNotArriveSaysSoAndCanBeAskedAgain() async {
        var script = loaded()
        script.request = [.failure(offline), .success(recordedRequest)]
        let (model, fake, spy) = await setup(script)
        await model.load()
        model.startDelete()

        await model.confirmDelete()
        #expect(model.toast == .noConnection)
        #expect(model.deletion == .idle)
        #expect(spy.count == 0)

        model.startDelete()
        await model.confirmDelete()
        #expect(spy.count == 1)
        #expect(await fake.calls.filter { $0 == "request" }.count == 2)
    }

    @Test func aCancelledRequestGoesBackToTheConfirmationQuietly() async {
        var script = loaded()
        script.cancelNextRequest = true
        let (model, _, spy) = await setup(script)
        await model.load()
        model.startDelete()

        await model.confirmDelete()

        #expect(model.deletion == .confirming)
        #expect(model.toast == nil)
        #expect(spy.count == 0)
    }

    // Review Focus 2.
    @Test func aRefreshKeepsTheConfirmationOpen() async {
        let (model, _, _) = await setup(loaded(times: 2), parents: [.success(owner), .success(owner)])
        await model.load()
        model.startDelete()

        await model.load()

        #expect(model.deletion == .confirming)
    }

    // Review Focus 2.
    @Test(.timeLimit(.minutes(5)))
    func aRefreshDuringTheRequestKeepsItSubmitting() async {
        let gate = PauseGate()
        var script = loaded(times: 2)
        script.request = [.success(recordedRequest)]
        script.requestGate = gate
        let (model, _, spy) = await setup(script, parents: [.success(owner), .success(owner)])
        await model.load()
        model.startDelete()

        let first = Task { await model.confirmDelete() }
        await gate.untilPaused()
        await model.load()
        #expect(model.deletion == .submitting)

        await gate.release()
        await first.value
        #expect(model.deletion == .requested(executableAt: deletionDate))
        #expect(spy.count == 1)
    }

    // Review Focus 3.
    // Fix round 1: a load in flight when the request succeeds must not undo it.
    @Test(.timeLimit(.minutes(5)))
    func aLoadInFlightWhenTheRequestSucceedsDoesNotBringTheButtonBack() async {
        let gate = PauseGate()
        var script = loaded(times: 2)
        script.request = [.success(recordedRequest)]
        let (model, fake, spy) = await setup(script, parents: [.success(owner), .success(owner)])
        await model.load()
        await fake.holdNextDisclosure(gate)

        let slow = Task { await model.load() }
        await gate.untilPaused()
        model.startDelete()
        await model.confirmDelete()
        #expect(model.deletion == .requested(executableAt: deletionDate))

        await gate.release()
        await slow.value
        #expect(model.deletion == .requested(executableAt: deletionDate))
        #expect(!model.canRequestDeletion)
        #expect(spy.count == 1)
        #expect(await fake.calls.filter { $0 == "request" }.count == 1)
    }

    @Test(.timeLimit(.minutes(5)))
    func anOlderLoadNeverOverwritesANewerOne() async {
        let gate = PauseGate()
        let newer = PrivacyDisclosure(
            documentVersion: "2026-10-07",
            locale: "uz",
            seen: sampleDisclosure.seen,
            notSeen: sampleDisclosure.notSeen
        )
        var script = FakePrivacy.Script()
        script.disclosure = [.success(sampleDisclosure), .success(newer)]
        script.current = [.success(nil), .success(nil)]
        script.disclosureGate = gate
        let (model, _, _) = await setup(script, parents: [.success(owner), .success(owner)])

        let first = Task { await model.load() }
        await gate.untilPaused()
        await model.load()
        #expect(model.disclosure == newer)

        await gate.release()
        await first.value
        #expect(model.disclosure == newer)
    }

    @Test func theConfirmationNamesTheWaitOnlyWhenTheServerGaveIt() async {
        let (withDays, _, _) = await setup(FakePrivacy.Script(), config: PrivacyConfig(deletionDelayDays: 7, policyURL: nil))
        let (withoutDays, _, _) = await setup(FakePrivacy.Script(), config: .absent)

        #expect(withDays.deleteBody(l10n) == l10n.privacyDeleteBodyWithDays(7))
        #expect(withoutDays.deleteBody(l10n) == l10n.privacyDeleteBody)
    }

    @Test func theCaptionNamesTheOnlyChildAndNoOneElse() async {
        let (one, _, _) = await setup(FakePrivacy.Script(), children: [makeChild("Ali")])
        let (two, _, _) = await setup(FakePrivacy.Script(), children: [makeChild("Ali"), makeChild("Vali")])
        let (none, _, _) = await setup(FakePrivacy.Script())
        let (blank, _, _) = await setup(FakePrivacy.Script(), children: [makeChild("  ")])

        #expect(one.caption(l10n) == l10n.privacyCaptionChild("Ali"))
        #expect(two.caption(l10n) == l10n.privacyCaptionChildren)
        #expect(none.caption(l10n) == l10n.privacyCaptionChildren)
        #expect(blank.caption(l10n) == l10n.privacyCaptionChildren)
    }
}
