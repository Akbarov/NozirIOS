import Foundation

/// The last config the server sent to *this* app version. Keyed by version
/// because `updateRequired` is the server's verdict on one version only.
public protocol ConfigCache: Sendable {
    func load(appVersion: String) -> ServerConfig?
    func save(_ config: ServerConfig, appVersion: String)
}

public final class UserDefaultsConfigCache: ConfigCache, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(appVersion: String) -> ServerConfig? {
        guard let data = defaults.data(forKey: key(appVersion)) else { return nil }
        return try? JSONDecoder().decode(ServerConfig.self, from: data)
    }

    public func save(_ config: ServerConfig, appVersion: String) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key(appVersion))
    }

    private func key(_ appVersion: String) -> String {
        "nozir.serverConfig.\(appVersion)"
    }
}
