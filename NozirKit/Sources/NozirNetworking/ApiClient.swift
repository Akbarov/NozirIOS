import Foundation

/// Builds requests, sends them, and turns every answer into either a value or
/// an `ApiFailure`. An authorised call that gets a 401 is refreshed once and
/// retried once; a second 401 is returned as it is.
public struct ApiClient: Sendable {
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let identity: ClientIdentity
    private let tokens: (any AccessTokenProvider)?

    public init(
        baseURL: URL,
        transport: any HTTPTransport,
        identity: ClientIdentity,
        tokens: (any AccessTokenProvider)? = nil
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.identity = identity
        self.tokens = tokens
    }

    public func withTokens(_ tokens: any AccessTokenProvider) -> ApiClient {
        ApiClient(baseURL: baseURL, transport: transport, identity: identity, tokens: tokens)
    }

    public func send<Response: Decodable>(_ request: ApiRequest, as type: Response.Type) async throws -> Response {
        let data = try await perform(request)
        do {
            return try NozirJSON.decoder().decode(Response.self, from: data)
        } catch {
            throw ApiFailure.decoding(String(describing: error))
        }
    }

    public func send(_ request: ApiRequest) async throws {
        _ = try await perform(request)
    }

    private func perform(_ request: ApiRequest) async throws -> Data {
        guard request.requiresAuth else {
            let answer = try await transmit(request, bearer: nil)
            return try checked(answer)
        }
        guard let tokens else { throw ApiFailure.sessionEnded }
        let token = try await tokens.validAccessToken()
        let first = try await transmit(request, bearer: token)
        guard first.response.statusCode == 401 else { return try checked(first) }
        let renewed = try await tokens.refreshAfterRejection(of: token)
        let second = try await transmit(request, bearer: renewed)
        return try checked(second)
    }

    private func transmit(
        _ request: ApiRequest,
        bearer: String?
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        let urlRequest = makeURLRequest(request, bearer: bearer)
        do {
            let (data, response) = try await transport.send(urlRequest)
            return (data, response)
        } catch let error as URLError {
            throw ApiFailure.network(code: error.code.rawValue)
        } catch {
            throw ApiFailure.network(code: URLError.Code.unknown.rawValue)
        }
    }

    private func checked(_ answer: (data: Data, response: HTTPURLResponse)) throws -> Data {
        let status = answer.response.statusCode
        guard (200..<300).contains(status) else {
            throw ResponseMapping.failure(status: status, body: answer.data)
        }
        return answer.data
    }

    func makeURLRequest(_ request: ApiRequest, bearer: String?) -> URLRequest {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + request.path) else {
            preconditionFailure("Unbuildable API path: \(request.path)")
        }
        if !request.query.isEmpty {
            components.queryItems = request.query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            preconditionFailure("Unbuildable API URL: \(request.path)")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue(identity.headerValue, forHTTPHeaderField: "X-Nozir-Client")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer {
            urlRequest.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        return urlRequest
    }
}
