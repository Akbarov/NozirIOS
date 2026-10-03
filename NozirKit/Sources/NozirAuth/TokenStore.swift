import Foundation

/// Where the session lives between launches. A future sign-in provider (for
/// example Sign in with Apple) ends the same way Telegram does: by saving here.
public protocol TokenStore: Sendable {
    func load() -> TokenPair?
    func save(_ tokens: TokenPair) throws
    func clear()
}

/// For tests and previews. Never used by the shipping app.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: TokenPair?

    public init(_ tokens: TokenPair? = nil) {
        self.tokens = tokens
    }

    public func load() -> TokenPair? {
        lock.withLock { tokens }
    }

    public func save(_ tokens: TokenPair) throws {
        lock.withLock { self.tokens = tokens }
    }

    public func clear() {
        lock.withLock { tokens = nil }
    }
}
