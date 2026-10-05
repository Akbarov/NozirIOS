import Foundation
import Testing
import NozirTestSupport
@testable import NozirNetworking

private func client() -> ApiClient {
    ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: FakeTransport([]),
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5")
    )
}

@Suite struct ApiRequestTests {
    @Test func aRuleWriteCarriesTheVersionItWasMadeAgainst() throws {
        struct Limit: Encodable { let schoolDayMinutes: Int }
        let request = try ApiRequest.put("/v1/parent/children/c1/rules/screen-time", json: Limit(schoolDayMinutes: 120), ifMatch: "\"7\"")

        let urlRequest = client().makeURLRequest(request, bearer: "acc")

        #expect(urlRequest.httpMethod == "PUT")
        #expect(urlRequest.value(forHTTPHeaderField: "If-Match") == "\"7\"")
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(urlRequest.jsonObject?["schoolDayMinutes"] as? Int == 120)
    }

    @Test func anOrdinaryRequestHasNoIfMatch() {
        let urlRequest = client().makeURLRequest(ApiRequest(method: .get, path: "/v1/parent/children"), bearer: "acc")

        #expect(urlRequest.value(forHTTPHeaderField: "If-Match") == nil)
    }

    @Test func patchSendsJSON() throws {
        struct Body: Encodable { let locale: String }
        let urlRequest = client().makeURLRequest(try .patch("/v1/parent/me", json: Body(locale: "ru")), bearer: "acc")

        #expect(urlRequest.httpMethod == "PATCH")
        #expect(urlRequest.jsonBody == ["locale": "ru"])
    }

    @Test func deleteSendsNoBody() {
        let urlRequest = client().makeURLRequest(ApiRequest(method: .delete, path: "/v1/parent/children/c1"), bearer: "acc")

        #expect(urlRequest.httpMethod == "DELETE")
        #expect(urlRequest.httpBody == nil)
    }

    @Test func notFoundIsRecognisedWithOrWithoutTheErrorBody() {
        #expect(ApiFailure.server(status: 404, error: ApiError(code: .notFound)).isNotFound)
        #expect(ApiFailure.unexpectedStatus(404).isNotFound)
        #expect(!ApiFailure.server(status: 400, error: ApiError(code: .validationFailed)).isNotFound)
    }
}
