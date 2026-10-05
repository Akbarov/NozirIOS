import Foundation
import Testing
import NozirFamily
import NozirL10n
@testable import NozirAppFeature

@MainActor
private func family(_ children: [Child]) async -> FamilyStore {
    var script = FakeFamily.Script()
    script.children = [.success(children)]
    let store = FamilyStore(service: FakeFamily(script))
    try? await store.refresh()
    return store
}

@MainActor
@Suite struct StatisticsModelTests {
    @Test func theFirstChildByDefault() async {
        let ali = makeChild("Ali"), vali = makeChild("Vali")
        let model = StatisticsModel(family: await family([ali, vali]))

        #expect(model.childId == ali.id)
        #expect(model.showsSwitcher)
        #expect(model.switcherChildren(L10n(.uz)).map(\.name) == ["Ali", "Vali"])
        #expect(model.switcherChildren(L10n(.uz)).map(\.accessibilityLabel) == [
            L10n(.uz).contentDescriptionChildAvatar("Ali"), L10n(.uz).contentDescriptionChildAvatar("Vali"),
        ])
    }

    @Test func aChoiceIsKept() async {
        let ali = makeChild("Ali"), vali = makeChild("Vali")
        let model = StatisticsModel(family: await family([ali, vali]))

        model.selectedChildId = vali.id

        #expect(model.childId == vali.id)
    }

    // Review Focus 4.
    @Test func aRemovedChildFallsBackToTheFirst() async {
        let ali = makeChild("Ali"), vali = makeChild("Vali")
        let store = await family([ali, vali])
        let model = StatisticsModel(family: store)
        model.selectedChildId = vali.id

        store.remove(vali.id)

        #expect(model.childId == ali.id)
        #expect(!model.showsSwitcher)
    }

    @Test func familyFailureThenRetry() async {
        var script = FakeFamily.Script()
        script.children = [.failure(.network(code: URLError.notConnectedToInternet.rawValue)), .success([makeChild("Ali")])]
        let store = FamilyStore(service: FakeFamily(script))
        let model = StatisticsModel(family: store)

        await model.loadFamily()
        #expect(model.familyFailure == .noConnection)
        #expect(!store.hasLoaded)

        await model.loadFamily()
        #expect(model.familyFailure == nil)
        #expect(store.hasLoaded)
        #expect(model.childId != nil)
    }

    @Test func noChildrenNoChild() async {
        let model = StatisticsModel(family: await family([]))

        #expect(model.childId == nil)
    }
}
