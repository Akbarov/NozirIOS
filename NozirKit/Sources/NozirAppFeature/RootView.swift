import SwiftUI
import NozirDesignSystem
import NozirL10n

/// Shows whichever top-level state AppModel is in, in the parent's language and
/// theme, and reports scene changes to it.
public struct RootView: View {
    private let environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NozirColor.background.ignoresSafeArea())
            .environment(\.l10n, environment.language.l10n)
            // SwiftUI's own pieces (date pickers, formatted numbers) follow the
            // app's language too, not the phone's.
            .environment(\.locale, Locale(identifier: environment.language.current.rawValue))
            .preferredColorScheme(environment.appearance.mode.colorScheme)
            .task { await environment.appModel.start() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    environment.appModel.sceneDidEnterBackground(at: Date())
                case .active:
                    Task { await environment.appModel.sceneDidBecomeActive(at: Date()) }
                default:
                    break
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch environment.appModel.phase {
        case .launching:
            ProgressView().tint(NozirColor.primary)
        case .updateRequired(let emergencyNumber):
            UpdateRequiredView(emergencyNumber: emergencyNumber, appStoreURL: environment.appStoreURL)
        case .signedOut:
            SignedOutFlow(environment: environment)
        case .signedIn:
            SignedInView(model: environment.makeSignedInModel())
        }
    }
}
