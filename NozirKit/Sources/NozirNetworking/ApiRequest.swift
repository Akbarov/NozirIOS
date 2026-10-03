import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

/// One call, described without knowing the host, the client header or the token.
public struct ApiRequest: Sendable {
    public var method: HTTPMethod
    /// Starts with "/", e.g. "/v1/config".
    public var path: String
    public var query: [String: String]
    public var body: Data?
    public var requiresAuth: Bool

    public init(
        method: HTTPMethod,
        path: String,
        query: [String: String] = [:],
        body: Data? = nil,
        requiresAuth: Bool = true
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
    }

    public static func post<Body: Encodable>(
        _ path: String,
        json body: Body,
        requiresAuth: Bool = true
    ) throws -> ApiRequest {
        ApiRequest(method: .post, path: path, body: try NozirJSON.encoder().encode(body), requiresAuth: requiresAuth)
    }
}
