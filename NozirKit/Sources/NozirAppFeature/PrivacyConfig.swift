import Foundation
import NozirConfig

/// What P20 takes from the server config. Both are the server's to state and
/// neither is the app's to invent: without a config there is no number of
/// days and no link (Android `PrivacyViewModel.loadServerConfig`).
struct PrivacyConfig: Equatable, Sendable {
    /// Positive, or nil: the confirmation then names no number.
    let deletionDelayDays: Int?
    /// A web page, or nil: the policy row is not drawn.
    let policyURL: URL?

    static let absent = PrivacyConfig(deletionDelayDays: nil, policyURL: nil)

    init(deletionDelayDays: Int?, policyURL: URL?) {
        self.deletionDelayDays = deletionDelayDays
        self.policyURL = policyURL
    }

    init(_ config: ServerConfig?) {
        guard let config else {
            self = .absent
            return
        }
        let days = config.dataDeletionDelayDays.flatMap { $0 > 0 ? $0 : nil }
        self.init(deletionDelayDays: days, policyURL: Self.webPage(config.privacyPolicyUrl))
    }

    private static func webPage(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
