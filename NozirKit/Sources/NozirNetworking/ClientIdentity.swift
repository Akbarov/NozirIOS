/// What this app is and what it runs on, sent as `X-Nozir-Client`.
///
/// Drives the server's minimum-version gate. It carries no device identifier
/// and must never become one: the OS version is a coarse class, not a name.
public struct ClientIdentity: Sendable, Equatable {
    public let appVersion: String
    public let osVersion: String

    public init(appVersion: String, osVersion: String) {
        self.appVersion = appVersion
        self.osVersion = osVersion
    }

    public var headerValue: String {
        "nozir-parent/\(appVersion) (ios; \(osVersion))"
    }
}
