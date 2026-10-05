public protocol ConfigLoading: Sendable {
    /// The server's config, or the last one this version saw, or nil.
    /// Never throws: no answer must never lock a parent out.
    func load() async -> ServerConfig?
}

public struct ConfigLoader: ConfigLoading {
    private let api: ConfigApi
    private let cache: any ConfigCache
    private let appVersion: String

    public init(api: ConfigApi, cache: any ConfigCache, appVersion: String) {
        self.api = api
        self.cache = cache
        self.appVersion = appVersion
    }

    public func load() async -> ServerConfig? {
        do {
            let config = try await api.fetch()
            cache.save(config, appVersion: appVersion)
            return config
        } catch {
            return cache.load(appVersion: appVersion)
        }
    }
}
