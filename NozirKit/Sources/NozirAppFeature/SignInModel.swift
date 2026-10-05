import Foundation
import Observation
import NozirAuth
import NozirNetworking

public enum SignInStage: Equatable, Sendable {
    case choice
    case telegramCode
}

/// P02: open the bot, then type the code it sent.
@MainActor
@Observable
public final class SignInModel {
    public private(set) var stage: SignInStage = .choice
    public private(set) var isBusy = false
    public private(set) var isTelegramAvailable = true
    public private(set) var code = ""
    public private(set) var codeLength = 6
    public private(set) var codeMinutes = 3
    public private(set) var message: String?
    public private(set) var botLink: URL?

    private let service: any TelegramSignInService
    private let onSignedIn: @MainActor () -> Void

    public init(service: any TelegramSignInService, onSignedIn: @escaping @MainActor () -> Void) {
        self.service = service
        self.onSignedIn = onSignedIn
    }

    public var canVerify: Bool {
        code.count == codeLength && !isBusy
    }

    /// Asks the server for the bot and returns the link to open, or nil when
    /// there is nothing to open (the reason is then in `message` or in
    /// `isTelegramAvailable`).
    public func chooseTelegram() async -> URL? {
        guard !isBusy else { return nil }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let started = try await service.start()
            codeLength = started.codeLength
            codeMinutes = max(1, Int((Double(started.codeTtlSeconds) / 60).rounded(.up)))
            botLink = started.deepLink
            code = ""
            stage = .telegramCode
            return started.deepLink
        } catch let failure as ApiFailure where failure.isServiceUnavailable {
            isTelegramAvailable = false
            return nil
        } catch {
            message = UserMessage.text(for: error)
            return nil
        }
    }

    public func telegramDidNotOpen() {
        message = Copy.SignIn.telegramNotOpened
    }

    /// Keeps ASCII digits only, up to the code's length: the backend accepts
    /// `[0-9]` and nothing else, and a pasted "123 456" is still the code.
    public func updateCode(_ input: String) {
        let digits = input.filter { $0.isASCII && $0.isNumber }
        code = String(digits.prefix(codeLength))
        message = nil
    }

    public func verify() async {
        guard canVerify else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await service.verify(code: code)
            onSignedIn()
        } catch let failure as ApiFailure where failure.code == .otpCodeInvalid || failure.code == .otpCodeExpired {
            // Wrong, expired and never-existed are one answer on the server; one here too.
            code = ""
            message = Copy.SignIn.codeRejected
        } catch {
            message = UserMessage.text(for: error)
        }
    }
}

extension ApiFailure {
    var isServiceUnavailable: Bool {
        guard case .server(let status, let error) = self else { return false }
        return status == 503 || error.code == .upstreamUnavailable
    }
}
