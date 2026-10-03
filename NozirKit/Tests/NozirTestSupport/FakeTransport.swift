import Foundation
import NozirNetworking

/// Answers requests from a script, in order, and remembers what it was asked.
/// An exhausted script behaves like a phone with no connection.
public actor FakeTransport: HTTPTransport {
    public struct Reply: Sendable {
        public let status: Int
        public let body: String

        public init(status: Int, body: String = "") {
            self.status = status
            self.body = body
        }
    }

    private var script: [Reply]
    public private(set) var requests: [URLRequest] = []

    public init(_ script: [Reply]) {
        self.script = script
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !script.isEmpty else { throw URLError(.notConnectedToInternet) }
        let reply = script.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(reply.body.utf8), response)
    }
}
