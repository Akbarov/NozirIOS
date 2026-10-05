/// Whether the "update the app" wall stands in front of a screen.
///
/// No config means no wall: being unable to reach the server is not a reason
/// to lock a parent out of a child-safety app. SOS is exempt, always.
public enum UpdateGate {
    public static func blocks(_ config: ServerConfig?, isExempt: Bool = false) -> Bool {
        guard !isExempt, let config else { return false }
        return config.updateRequired
    }
}
