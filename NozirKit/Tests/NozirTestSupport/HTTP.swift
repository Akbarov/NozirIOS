import Foundation

public extension FakeTransport.Reply {
    static func ok(_ body: String) -> Self {
        .init(status: 200, body: body)
    }

    /// The backend's error body with the given code.
    static func error(_ status: Int, code: String) -> Self {
        .init(status: status, body: #"{"error":{"code":"\#(code)","message":"server text"}}"#)
    }
}

public extension URLRequest {
    /// The body as a flat JSON object, for asserting what was sent.
    var jsonBody: [String: String]? {
        guard let httpBody else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: httpBody)
    }
}
