import Foundation
import Testing
import NozirTestSupport
@testable import NozirFamily

@MainActor
@Suite struct FamilyStoreTests {
    @Test func refreshingReplacesTheList() async throws {
        let (api, _) = familyApi([.ok("[\(childJSON())]")])
        let store = FamilyStore(service: api)

        try await store.refresh()

        #expect(store.children.map(\.displayName) == ["Ali"])
        #expect(store.hasLoaded)
    }

    @Test func aFailedRefreshKeepsWhatWasThere() async throws {
        let (api, _) = familyApi([.ok("[\(childJSON())]")])
        let store = FamilyStore(service: api)
        try await store.refresh()

        await #expect(throws: (any Error).self) { try await store.refresh() }

        #expect(store.children.count == 1)
    }

    @Test func aChangedChildReplacesItsOldSelfAndANewOneIsAdded() {
        let store = FamilyStore(service: familyApi([]).0)
        let ali = Child(id: aliId, displayName: "Ali", birthYear: 2015)

        store.replace(ali)
        store.replace(Child(id: aliId, displayName: "Alisher", birthYear: 2015))
        store.replace(Child(id: UUID(), displayName: "Vali", birthYear: 2013))

        #expect(store.children.map(\.displayName) == ["Alisher", "Vali"])
        #expect(store.child(aliId)?.displayName == "Alisher")
    }

    @Test func aRemovedChildIsGone() {
        let store = FamilyStore(service: familyApi([]).0)
        store.replace(Child(id: aliId, displayName: "Ali", birthYear: 2015))

        store.remove(aliId)

        #expect(store.children.isEmpty)
    }
}
