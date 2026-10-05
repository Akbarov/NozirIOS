import Foundation
import Observation
import NozirDesignSystem
import NozirFamily

/// What P03 collects. Nothing reaches the server until P03b saves it.
public struct ChildDraft: Hashable, Sendable {
    public let displayName: String
    public let birthYear: Int
    public let avatarKey: String
    public let phoneE164: String?

    var create: ChildCreate {
        ChildCreate(displayName: displayName, birthYear: birthYear, avatarKey: avatarKey, phoneE164: phoneE164)
    }
}

/// The rules P03 and the child details screen share.
enum ChildAge {
    /// The backend's age bands cover 7–17; Android accepts the same.
    static let range = 7...17
    /// `CreateChildBody.displayName` max length.
    static let nameLimit = 40

    static func of(birthYearText: String, currentYear: Int) -> Int? {
        guard birthYearText.count == 4, let year = Int(birthYearText) else { return nil }
        let age = currentYear - year
        return range.contains(age) ? age : nil
    }

    static func yearDigits(from input: String) -> String {
        String(input.filter { $0.isASCII && $0.isNumber }.prefix(4))
    }

    static func name(from input: String) -> String {
        String(input.prefix(nameLimit))
    }
}

/// P03 (Android `AddChildForm`).
@MainActor
@Observable
public final class AddChildModel {
    public private(set) var name = ""
    public private(set) var birthYearText = ""
    public private(set) var phoneDigits = ""
    public var avatar: AvatarTone = .teal
    private let currentYear: Int

    public init(currentYear: Int = Calendar.current.component(.year, from: Date())) {
        self.currentYear = currentYear
    }

    public func updateName(_ input: String) {
        name = ChildAge.name(from: input)
    }

    public func updateBirthYear(_ input: String) {
        birthYearText = ChildAge.yearDigits(from: input)
    }

    public func updatePhone(_ input: String) {
        phoneDigits = UzbekPhone.digits(from: input)
    }

    public var age: Int? {
        ChildAge.of(birthYearText: birthYearText, currentYear: currentYear)
    }

    /// Empty is fine (a child without a number of their own); half a number is not.
    public var showsPhoneError: Bool {
        !phoneDigits.isEmpty && phoneDigits.count != UzbekPhone.subscriberDigits
    }

    public var draft: ChildDraft? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, age != nil, !showsPhoneError, let year = Int(birthYearText) else { return nil }
        return ChildDraft(displayName: trimmed, birthYear: year, avatarKey: avatar.rawValue, phoneE164: UzbekPhone.e164(phoneDigits))
    }

    public var canContinue: Bool {
        draft != nil
    }
}
