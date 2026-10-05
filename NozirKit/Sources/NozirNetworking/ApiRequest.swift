import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// One call, described without knowing the host, the client header or the token.
public struct ApiRequest: Sendable {
    public var method: HTTPMethod
    /// Starts with "/", e.g. "/v1/config".
    public var path: String
    public var query: [String: String]
    public var body: Data?
    public var requiresAuth: Bool
    /// Seconds before the request gives up; nil keeps URLSession's default (60 s).
    public var timeout: TimeInterval?
    /// The entity tag a write was made against, e.g. `"7"` with the quotes
    /// (`IfMatchVersion.kt`). Every rules write needs one.
    public var ifMatch: String?

    public init(
        method: HTTPMethod,
        path: String,
        query: [String: String] = [:],
        body: Data? = nil,
        requiresAuth: Bool = true,
        timeout: TimeInterval? = nil,
        ifMatch: String? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
        self.timeout = timeout
        self.ifMatch = ifMatch
    }

    public static func post<Body: Encodable>(
        _ path: String,
        json body: Body,
        requiresAuth: Bool = true
    ) throws -> ApiRequest {
        ApiRequest(method: .post, path: path, body: try NozirJSON.encoder().encode(body), requiresAuth: requiresAuth)
    }

    public static func put<Body: Encodable>(_ path: String, json body: Body, ifMatch: String? = nil) throws -> ApiRequest {
        ApiRequest(method: .put, path: path, body: try NozirJSON.encoder().encode(body), ifMatch: ifMatch)
    }

    public static func patch<Body: Encodable>(_ path: String, json body: Body) throws -> ApiRequest {
        ApiRequest(method: .patch, path: path, body: try NozirJSON.encoder().encode(body))
    }
}
