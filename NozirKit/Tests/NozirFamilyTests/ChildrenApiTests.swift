import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirFamily

@Suite struct ChildrenApiTests {
    @Test func theListReadsTheServersShape() async throws {
        let (api, transport) = familyApi([.ok("[\(childJSON(phone: "\"+998901234567\""))]")])

        let children = try await api.children()

        #expect(children == [Child(
            id: aliId,
            displayName: "Ali",
            birthYear: 2015,
            ageGroup: .star,
            avatarKey: "teal",
            phoneE164: "+998901234567",
            pairingState: .notPaired
        )])
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/parent/children")
    }

    @Test func aChildInAStateThisAppDoesNotKnowStillLoads() async throws {
        let (api, _) = familyApi([.ok("[\(childJSON(ageGroup: "TODDLER", pairingState: "SOMETHING_NEW"))]")])

        let child = try #require(try await api.children().first)

        #expect(child.ageGroup == nil)
        #expect(child.pairingState == .notPaired)
    }

    @Test func creatingSendsOnlyWhatTheParentGave() async throws {
        let (api, transport) = familyApi([.init(status: 201, body: childJSON())])

        let child = try await api.createChild(ChildCreate(displayName: "Ali", birthYear: 2015, avatarKey: "teal", phoneE164: nil))

        #expect(child.id == aliId)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/parent/children")
        let body = try #require(request.jsonObject)
        #expect(Set(body.keys) == ["displayName", "birthYear", "avatarKey"])
        #expect(body["birthYear"] as? Int == 2015)
    }

    @Test func theChildLimitIsTheServersAnswer() async {
        let (api, _) = familyApi([.error(403, code: "CHILD_LIMIT_REACHED")])

        do {
            _ = try await api.createChild(ChildCreate(displayName: "Ali", birthYear: 2015, avatarKey: nil, phoneE164: nil))
            Issue.record("expected the limit")
        } catch let failure as ApiFailure {
            #expect(failure.code == .childLimitReached)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func anEditSendsOnlyWhatChanged() async throws {
        let (api, transport) = familyApi([.ok(childJSON(name: "Vali"))])

        let child = try await api.updateChild(aliId, ChildUpdate(displayName: "Vali"))

        #expect(child.displayName == "Vali")
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/parent/children/\(aliId.uuidString.lowercased())")
        #expect(request.jsonBody == ["displayName": "Vali"])
    }

    @Test func clearingThePhoneSendsAnExplicitNull() async throws {
        let (api, transport) = familyApi([.ok(childJSON())])

        _ = try await api.updateChild(aliId, ChildUpdate(phone: .cleared))

        let body = try #require(await transport.requests.first?.jsonObject)
        #expect(Set(body.keys) == ["phoneE164"])
        #expect(body["phoneE164"] is NSNull)
    }

    @Test func anUnchangedPhoneIsNotSentAtAll() {
        #expect(ChildUpdate().isEmpty)
        #expect(!ChildUpdate(phone: .set("+998901234567")).isEmpty)
    }

    @Test func removingSendsDelete() async throws {
        let (api, transport) = familyApi([.init(status: 204)])

        try await api.removeChild(aliId)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/parent/children/\(aliId.uuidString.lowercased())")
    }

    @Test func oneChildIsReadByItsId() async throws {
        let (api, transport) = familyApi([.ok(childJSON(pairingState: "PAIRED"))])

        let child = try await api.child(aliId)

        #expect(child.pairingState == .paired)
        #expect(await transport.requests.first?.url?.path == "/v1/parent/children/\(aliId.uuidString.lowercased())")
    }
}
