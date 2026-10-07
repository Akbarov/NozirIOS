/// `ServerConfigResponse`, reduced to what the app reads.
public struct ServerConfig: Codable, Equatable, Sendable {
    public let minSupportedVersion: String
    public let latestVersion: String
    /// Computed by the server from `X-Nozir-Client` (`ClientVersions.isBelow`).
    public let updateRequired: Bool
    public let featureFlags: [String: Bool]
    public let emergencyContacts: EmergencyContacts
    public let privacyPolicyUrl: String
    public let termsUrl: String
    public let supportUrl: String
    /// How long a deletion request waits before it runs (P20). Nil from an
    /// older server or a config cached before the field existed.
    public let dataDeletionDelayDays: Int?

    public init(
        minSupportedVersion: String,
        latestVersion: String,
        updateRequired: Bool,
        featureFlags: [String: Bool],
        emergencyContacts: EmergencyContacts,
        privacyPolicyUrl: String,
        termsUrl: String,
        supportUrl: String,
        dataDeletionDelayDays: Int? = nil
    ) {
        self.minSupportedVersion = minSupportedVersion
        self.latestVersion = latestVersion
        self.updateRequired = updateRequired
        self.featureFlags = featureFlags
        self.emergencyContacts = emergencyContacts
        self.privacyPolicyUrl = privacyPolicyUrl
        self.termsUrl = termsUrl
        self.supportUrl = supportUrl
        self.dataDeletionDelayDays = dataDeletionDelayDays
    }
}

public struct EmergencyContacts: Codable, Equatable, Sendable {
    public let emergencyNumber: String
    public let policeNumber: String
    public let ambulanceNumber: String
    public let fireNumber: String
    public let childHelplineNumber: String
    public let isChildHelplineEnabled: Bool

    public init(
        emergencyNumber: String,
        policeNumber: String,
        ambulanceNumber: String,
        fireNumber: String,
        childHelplineNumber: String,
        isChildHelplineEnabled: Bool
    ) {
        self.emergencyNumber = emergencyNumber
        self.policeNumber = policeNumber
        self.ambulanceNumber = ambulanceNumber
        self.fireNumber = fireNumber
        self.childHelplineNumber = childHelplineNumber
        self.isChildHelplineEnabled = isChildHelplineEnabled
    }
}
