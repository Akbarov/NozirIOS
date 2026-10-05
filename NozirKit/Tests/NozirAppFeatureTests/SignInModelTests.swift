import Foundation
import Testing
@testable import NozirAuth
import NozirNetworking
@testable import NozirAppFeature

private let botStart = TelegramLoginStart(
    botUsername: "nozir_bot",
    deepLink: URL(string: "https://t.me/nozir_bot")!,
    codeLength: 6,
    codeTtlSeconds: 180
)

private actor FakeTelegram: TelegramSignInService {
    private let startResult: Result<TelegramLoginStart, ApiFailure>
    private let verifyResult: Result<Void, ApiFailure>
    private(set) var verifiedCodes: [String] = []

    init(start: Result<TelegramLoginStart, ApiFailure> = .success(botStart), verify: Result<Void, ApiFailure> = .success(())) {
        self.startResult = start
        self.verifyResult = verify
    }

    func start() async throws -> TelegramLoginStart {
        try startResult.get()
    }

    func verify(code: String) async throws {
        verifiedCodes.append(code)
        try verifyResult.get()
    }
}

private func failure(_ status: Int, _ code: ApiErrorCode, retryAfter: Int? = nil) -> ApiFailure {
    .server(status: status, error: ApiError(code: code, retryAfterSeconds: retryAfter))
}

@MainActor
@Suite struct SignInModelTests {
    @Test func choosingTelegramOpensTheBotAndAsksForTheCode() async {
        let model = SignInModel(service: FakeTelegram(), onSignedIn: {})

        let link = await model.chooseTelegram()

        #expect(link == URL(string: "https://t.me/nozir_bot"))
        #expect(model.stage == .telegramCode)
        #expect(model.codeLength == 6)
        #expect(model.codeMinutes == 3)
        #expect(model.isBusy == false)
    }

    @Test func aServerWithoutABotTurnsTheButtonOff() async {
        let model = SignInModel(service: FakeTelegram(start: .failure(failure(503, .upstreamUnavailable))), onSignedIn: {})

        let link = await model.chooseTelegram()

        #expect(link == nil)
        #expect(model.isTelegramAvailable == false)
        #expect(model.stage == .choice)
    }

    @Test func noConnectionWhileStartingSaysSo() async {
        let offline = ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue)
        let model = SignInModel(service: FakeTelegram(start: .failure(offline)), onSignedIn: {})

        _ = await model.chooseTelegram()

        #expect(model.message == Copy.Errors.noConnection)
        #expect(model.isTelegramAvailable)
    }

    // Review Focus 4.
    @Test(arguments: zip(
        ["123456", "123 456", "12-34-56", "1234567890", "١٢٣٤٥٦", "12a3"],
        ["123456", "123456", "123456", "123456", "", "123"]
    ))
    func theCodeKeepsOnlyASCIIDigitsUpToItsLength(typed: String, kept: String) async {
        let model = SignInModel(service: FakeTelegram(), onSignedIn: {})
        _ = await model.chooseTelegram()

        model.updateCode(typed)

        #expect(model.code == kept)
    }

    @Test func verifyIsOnlyPossibleWithAFullCode() async {
        let model = SignInModel(service: FakeTelegram(), onSignedIn: {})
        _ = await model.chooseTelegram()

        model.updateCode("12345")
        #expect(!model.canVerify)
        model.updateCode("123456")
        #expect(model.canVerify)
    }

    @Test func aGoodCodeSignsIn() async {
        let telegram = FakeTelegram()
        var signedIn = false
        let model = SignInModel(service: telegram, onSignedIn: { signedIn = true })
        _ = await model.chooseTelegram()
        model.updateCode("123456")

        await model.verify()

        #expect(await telegram.verifiedCodes == ["123456"])
        #expect(signedIn)
    }

    @Test(arguments: [ApiErrorCode.otpCodeInvalid, .otpCodeExpired])
    func aRejectedCodeIsClearedAndExplained(code: ApiErrorCode) async {
        let model = SignInModel(service: FakeTelegram(verify: .failure(failure(400, code))), onSignedIn: {})
        _ = await model.chooseTelegram()
        model.updateCode("123456")

        await model.verify()

        #expect(model.code == "")
        #expect(model.message == Copy.SignIn.codeRejected)
    }

    @Test func tooManyAttemptsSaysHowLongToWait() async {
        let model = SignInModel(service: FakeTelegram(verify: .failure(failure(429, .rateLimited, retryAfter: 42))), onSignedIn: {})
        _ = await model.chooseTelegram()
        model.updateCode("123456")

        await model.verify()

        #expect(model.message == Copy.Errors.rateLimited(seconds: 42))
        #expect(model.code == "123456")
    }

    @Test func telegramNotOpeningIsSaidPlainly() async {
        let model = SignInModel(service: FakeTelegram(), onSignedIn: {})
        _ = await model.chooseTelegram()

        model.telegramDidNotOpen()

        #expect(model.message == Copy.SignIn.telegramNotOpened)
    }

    @Test func typingClearsAnOldMessage() async {
        let model = SignInModel(service: FakeTelegram(), onSignedIn: {})
        _ = await model.chooseTelegram()
        model.telegramDidNotOpen()

        model.updateCode("1")

        #expect(model.message == nil)
    }
}

@Suite struct UserMessageTests {
    @Test func theServerMessageIsNeverShown() {
        let failure = ApiFailure.server(status: 500, error: ApiError(code: .internalError, message: "NullPointerException at line 42"))
        #expect(UserMessage.text(for: failure) == Copy.Errors.serverProblem)
    }

    @Test func aTimeoutIsNotCalledANoConnection() {
        let timeout = ApiFailure.network(code: URLError.Code.timedOut.rawValue)
        #expect(UserMessage.text(for: timeout) == Copy.Errors.timeout)
    }

    @Test func rateLimitedWithoutASecondsCountStillReads() {
        #expect(UserMessage.text(for: failure(429, .rateLimited)) == Copy.Errors.rateLimited(seconds: nil))
    }

    @Test func anErrorThatIsNotAnApiFailureIsAServerProblem() {
        struct Odd: Error {}
        #expect(UserMessage.text(for: Odd()) == Copy.Errors.serverProblem)
    }
}
