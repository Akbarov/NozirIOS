import Foundation
import Testing
import NozirDesignSystem
import NozirFamily
@testable import NozirAppFeature

@MainActor
private func setup(_ script: FakeFamily.Script = .init(), child: Child) -> (ChildDetailsModel, FakeFamily, FamilyStore) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(child)
    return (ChildDetailsModel(child: child, family: family, currentYear: 2026), fake, family)
}

@MainActor
@Suite struct ChildDetailsModelTests {
    @Test func theFormStartsFromTheChildWithNothingToSave() {
        let (model, _, _) = setup(child: makeChild("Ali", birthYear: 2015, phone: "+998901234567", avatar: "sky"))

        #expect(model.name == "Ali")
        #expect(model.birthYearText == "2015")
        #expect(model.phoneDigits == "901234567")
        #expect(model.avatar == .sky)
        #expect(model.changes.isEmpty)
        #expect(!model.canSave)
    }

    @Test func onlyWhatChangedIsSentAndTheFormStartsAgainFromTheAnswer() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.update = [.success(makeChild("Alisher", id: ali.id))]
        let (model, fake, family) = setup(script, child: ali)

        model.updateName("Alisher")
        await model.save()

        #expect(await fake.updates == [ChildUpdate(displayName: "Alisher")])
        #expect(model.wasSaved)
        #expect(family.child(ali.id)?.displayName == "Alisher")
        #expect(!model.canSave)
    }

    @Test func emptyingThePhoneRemovesIt() {
        let (model, _, _) = setup(child: makeChild("Ali", phone: "+998901234567"))

        model.updatePhone("")

        #expect(model.changes == ChildUpdate(phone: .cleared))
        #expect(model.canSave)
    }

    @Test func aNewNumberIsSentWhole() {
        let (model, _, _) = setup(child: makeChild("Ali"))

        model.updatePhone("901112233")

        #expect(model.changes.phone == .set("+998901112233"))
    }

    @Test func anUnknownColourIsNotRewrittenBehindTheParentsBack() {
        let (model, _, _) = setup(child: makeChild("Ali", avatar: "violet"))

        #expect(model.avatar == .teal)
        #expect(model.changes.isEmpty)
    }

    @Test func aStoredYearOutsideTheBandDoesNotBlockOtherEdits() {
        let (model, _, _) = setup(child: makeChild("Ali", birthYear: 2005))

        model.updateName("Alisher")

        #expect(model.canSave)
    }

    @Test func aNewYearOutsideTheBandCannotBeSaved() {
        let (model, _, _) = setup(child: makeChild("Ali", birthYear: 2015))

        model.updateBirthYear("2021")

        #expect(!model.canSave)
    }

    @Test func removingAsksFirstThenRemoves() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.remove = [.success(())]
        let (model, fake, family) = setup(script, child: ali)

        model.askToRemove()
        #expect(model.removal == .confirming)
        #expect(await fake.calls.isEmpty)

        await model.confirmRemove()

        #expect(model.wasRemoved)
        #expect(family.children.isEmpty)
    }

    @Test func aFailedRemovalAsksAgain() async {
        let (model, _, family) = setup(child: makeChild("Ali"))
        model.askToRemove()

        await model.confirmRemove()

        #expect(!model.wasRemoved)
        #expect(model.removal == .confirming)
        #expect(model.message == .noConnection)
        #expect(family.children.count == 1)
    }

    @Test func aFrozenChildCanBeMadeTheActiveOne() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        script.activeChild = [.success(Subscription(activeChildId: ali.id))]
        let (model, _, _) = setup(script, child: ali)

        await model.loadPlan()
        #expect(model.isFrozen)

        await model.makeActive()
        #expect(!model.isFrozen)
    }

    @Test func anUnknownPlanFreezesNobody() async {
        let (model, _, _) = setup(child: makeChild("Ali"))

        await model.loadPlan()

        #expect(!model.isFrozen)
    }
}
