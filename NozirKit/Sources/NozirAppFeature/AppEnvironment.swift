import Foundation
import NozirAuth
import NozirConfig
import NozirDesignSystem
import NozirFamily
import NozirL10n
import NozirNetworking

/// Every live object, built once at launch and wired here and nowhere else.
@MainActor
public final class AppEnvironment {
    public let appModel: AppModel
    public let language: LanguageStore
    public let appearance: AppearanceStore
    /// Nil until the app has an App Store ID (no developer account yet).
    let appStoreURL: URL?
    private let authorised: ApiClient
    private let telegramSignIn: any TelegramSignInService

    init(
        appModel: AppModel,
        language: LanguageStore,
        appearance: AppearanceStore,
        authorised: ApiClient,
        telegramSignIn: any TelegramSignInService,
        appStoreURL: URL?
    ) {
        self.appModel = appModel
        self.language = language
        self.appearance = appearance
        self.authorised = authorised
        self.telegramSignIn = telegramSignIn
        self.appStoreURL = appStoreURL
    }

    public static func live(baseURL: URL, appVersion: String, osVersion: String, deviceLabel: String) -> AppEnvironment {
        let identity = ClientIdentity(appVersion: appVersion, osVersion: osVersion)
        let anonymous = ApiClient(baseURL: baseURL, transport: URLSessionTransport(), identity: identity)
        let store = KeychainTokenStore()
        // Reinstalling the app signs the parent out (user decision); must run
        // before anything reads the store.
        FreshInstall.clearSessionLeftByPreviousInstall(store: store)
        // Refresh goes through the anonymous client: refreshing must never
        // itself need a fresh access token.
        let anonymousAuth = AuthApi(client: anonymous)
        let refresher = TokenRefresher(store: store, refresh: { try await anonymousAuth.refresh($0) })
        let authorised = anonymous.withTokens(refresher)
        let authorisedAuth = AuthApi(client: authorised)
        let config = ConfigLoader(
            api: ConfigApi(client: anonymous),
            cache: UserDefaultsConfigCache(),
            appVersion: appVersion
        )
        let appModel = AppModel(
            config: config,
            tokens: store,
            sessionEnded: refresher.sessionEnded,
            logout: { try await authorisedAuth.logout() }
        )
        return AppEnvironment(
            appModel: appModel,
            language: LanguageStore(),
            appearance: AppearanceStore(),
            authorised: authorised,
            telegramSignIn: TelegramSignIn(api: anonymousAuth, store: store, deviceLabel: deviceLabel),
            appStoreURL: nil
        )
    }

    func makeSignInModel() -> SignInModel {
        SignInModel(service: telegramSignIn, onSignedIn: { [appModel] in appModel.didSignIn() })
    }

    func makeSignedInModel() -> SignedInModel {
        let api = FamilyApi(client: authorised)
        return SignedInModel(
            family: FamilyStore(service: api),
            language: language,
            appearance: appearance,
            localeSync: LocaleSync(store: language, send: { _ = try await api.updateLocale($0) }),
            signOut: { [appModel] in await appModel.signOut() }
        )
    }
}
