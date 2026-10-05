import Foundation

/// Which server the app talks to. One host for every build, as on Android.
/// A Debug build can be pointed elsewhere with the scheme's environment
/// variable `NOZIR_API_BASE_URL` (Edit Scheme → Run → Arguments).
enum ApiHost {
    static let production = URL(string: "https://nozir.syncoder.uz")!

    static var current: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["NOZIR_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        #endif
        return production
    }
}
