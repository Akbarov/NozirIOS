import Foundation
import NozirFamily
import NozirInsights
import NozirL10n

/// What the SOS banner and P15 say and dial. The name is the alarm's own,
/// else the family list's (a removed child has neither); the child's number is
/// the alarm's own when P15 has it, else the family list's.
struct SosAlert: Equatable {
    let sos: ActiveSos
    let childName: String?
    let childPhone: String?
    let emergencyNumber: String?

    init(_ sos: ActiveSos, child: Child?, emergencyNumber: String?, phone: String? = nil) {
        self.sos = sos
        childName = Self.present(sos.childName) ?? Self.present(child?.displayName)
        childPhone = Self.present(phone) ?? Self.present(child?.phoneE164)
        self.emergencyNumber = Self.present(emergencyNumber)
    }

    func title(_ l10n: L10n) -> String {
        childName.map(l10n.homeSosBannerTitleNamed) ?? l10n.homeSosBannerTitle
    }

    /// "5 daqiqa oldin · hali javob berilmadi".
    func when(now: Date, _ l10n: L10n) -> String {
        l10n.homeSosBannerBodyWhen(ElapsedTime(from: sos.triggeredAt, to: now).text(l10n))
    }

    func callChildTitle(_ l10n: L10n) -> String {
        childName.map(l10n.sosActionCallChild) ?? l10n.sosActionCallChildUnnamed
    }

    var childCallURL: URL? {
        childPhone.flatMap { Self.dialURL($0) }
    }

    func emergencyTitle(_ l10n: L10n) -> String? {
        emergencyNumber.map(l10n.sosActionCallEmergency)
    }

    var emergencyCallURL: URL? {
        emergencyNumber.flatMap { Self.dialURL($0) }
    }

    /// `tel:` with only `+` and digits: spaces and dashes break the URL.
    private static func dialURL(_ number: String) -> URL? {
        let dialable = number.filter { $0 == "+" || $0.isASCII && $0.isNumber }
        return dialable.isEmpty ? nil : URL(string: "tel:\(dialable)")
    }

    private static func present(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
