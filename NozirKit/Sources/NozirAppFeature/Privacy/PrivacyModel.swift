import Foundation
import Observation
import NozirFamily
import NozirInsights
import NozirL10n
import NozirPrivacy

/// P20 (Android `PrivacyViewModel`): what the parent sees and what they do not,
/// read from the server and never from a copy in the app, and the request to
/// erase the family. Nothing is deleted here: the server records a request and
/// revokes every parent's session, so a recorded request ends this one locally.
@MainActor
@Observable
final class PrivacyModel {
    enum Deletion: Equatable {
        /// The current request could not be read: the section is not drawn.
        case unknown
        case idle
        case confirming
        case submitting
        case requested(executableAt: Date)
    }

    private(set) var disclosure: PrivacyDisclosure?
    /// The list could not be had and there is none on screen.
    private(set) var loadFailure: UserMessage?
    /// A list is on screen but the last refresh found no connection.
    private(set) var isOffline = false
    private(set) var deletion: Deletion = .unknown
    /// Only an owner may ask (a guardian gets 403); an unread role is not an owner.
    private(set) var isOwner = false
    /// A request that failed, said once; the view sets it back to nil.
    var toast: UserMessage?

    let config: PrivacyConfig
    private let privacy: any PrivacyService
    private let family: FamilyStore
    private let calendar: Calendar
    private let onSignedOut: @MainActor () -> Void
    /// Bumped by every load: an older answer never overwrites a newer one.
    @ObservationIgnored private var generation = 0

    init(
        privacy: any PrivacyService,
        family: FamilyStore,
        config: PrivacyConfig,
        calendar: Calendar = PrivacyModel.phoneCalendar,
        onSignedOut: @escaping @MainActor () -> Void
    ) {
        self.privacy = privacy
        self.family = family
        self.config = config
        self.calendar = calendar
        self.onSignedOut = onSignedOut
    }

    /// The date a parent reads: Gregorian, in the phone's time zone.
    nonisolated static var phoneCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// The list, the current request and the parent's role, asked together.
    func load() async {
        generation += 1
        let mine = generation
        if disclosure == nil {
            loadFailure = nil
        }
        let service = privacy
        let familyService = family.service
        async let shown = Self.attempt { try await service.disclosure() }
        async let current = Self.attempt { try await service.currentDeletion() }
        async let parent = Self.attempt { try await familyService.me() }
        let answers = await (shown, current, parent)
        guard mine == generation else { return }
        apply(disclosure: answers.0)
        apply(current: answers.1)
        if case .success(let me) = answers.2 {
            isOwner = me.role == "OWNER"
        }
    }

    var canRequestDeletion: Bool {
        deletion == .idle && isOwner
    }

    /// Opens the confirmation. Nothing has been sent.
    func startDelete() {
        guard canRequestDeletion else { return }
        deletion = .confirming
    }

    func cancelDelete() {
        guard deletion == .confirming else { return }
        deletion = .idle
    }

    /// Reachable from the confirmation only, so a second tap while the first
    /// is in flight does nothing. Never retried by itself.
    func confirmDelete() async {
        guard deletion == .confirming else { return }
        deletion = .submitting
        do {
            let recorded = try await privacy.requestDeletion()
            deletion = .requested(executableAt: recorded.executableAt)
            onSignedOut()
        } catch is CancellationError {
            deletion = .confirming
        } catch {
            deletion = .idle
            toast = UserMessage(error)
        }
    }

    /// Names the child only when there is exactly one to name (Android `loadChildName`).
    func caption(_ l10n: L10n) -> String {
        guard family.children.count == 1, let only = family.children.first else {
            return l10n.privacyCaptionChildren
        }
        let name = only.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? l10n.privacyCaptionChildren : l10n.privacyCaptionChild(name)
    }

    /// States the wait only when the server gave one.
    func deleteBody(_ l10n: L10n) -> String {
        guard let days = config.deletionDelayDays else { return l10n.privacyDeleteBody }
        return l10n.privacyDeleteBodyWithDays(days)
    }

    /// The server's date, the only one this screen quotes.
    func requestedBody(_ executableAt: Date, _ l10n: L10n) -> String {
        l10n.privacyDeleteRequestedBody(DateTexts.dayMonthAndYear(LocalDate(executableAt, in: calendar), l10n))
    }

    private func apply(disclosure answer: Result<PrivacyDisclosure, any Error>) {
        switch answer {
        case .success(let fresh):
            disclosure = fresh
            loadFailure = nil
            isOffline = false
        case .failure(let error):
            if error is CancellationError { return }
            let message = UserMessage(error)
            if disclosure == nil {
                loadFailure = message
            } else {
                isOffline = message == .noConnection || message == .timeout
            }
        }
    }

    /// A failure leaves `.unknown` unknown and a known stage as it was; an
    /// answer never pulls an open confirmation or a request in flight back.
    private func apply(current answer: Result<ErasureRequestStatus?, any Error>) {
        guard case .success(let status) = answer else { return }
        switch deletion {
        case .confirming, .submitting:
            return
        case .unknown, .idle, .requested:
            deletion = status.map { .requested(executableAt: $0.executableAt) } ?? .idle
        }
    }

    private nonisolated static func attempt<Value: Sendable>(
        _ work: @Sendable () async throws -> Value
    ) async -> Result<Value, any Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }
}
