import SwiftUI
import UIKit
import NozirAppFeature

@main
struct NozirApp: App {
    @State private var environment: AppEnvironment

    init() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        _environment = State(initialValue: AppEnvironment.live(
            baseURL: ApiHost.current,
            appVersion: version,
            osVersion: UIDevice.current.systemVersion,
            deviceLabel: UIDevice.current.model
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
    }
}
