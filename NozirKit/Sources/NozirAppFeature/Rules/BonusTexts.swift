import Foundation
import NozirFamily
import NozirL10n

/// P12's words (Android `BonusCeilingCard`, `BonusChallengeRow`, `ChallengeLabel`).
/// The names are the app's, not the server's: a kind added later has none.
enum BonusTexts {
    static func ceilingValue(_ minutes: Int, _ l10n: L10n) -> String {
        l10n.bonusCeilingValue(Durations.short(minutes, l10n))
    }

    /// Under the slider: zero turns task time off; a ceiling below what the
    /// enabled tasks pay says where it stops them. Otherwise nothing.
    static func ceilingNote(_ config: BonusConfig, _ l10n: L10n) -> String? {
        if config.maxDailyBonusMinutes == 0 { return l10n.bonusCeilingZero }
        guard config.isCeilingBinding else { return nil }
        return l10n.bonusCeilingBinding(
            Durations.short(config.earnableMinutes, l10n),
            Durations.short(config.maxDailyBonusMinutes, l10n)
        )
    }

    static func name(_ kind: ChallengeKind, _ l10n: L10n) -> String? {
        switch kind {
        case .math: l10n.bonusChallengeMath
        case .reading: l10n.bonusChallengeReading
        case .english: l10n.bonusChallengeEnglish
        case .exercise: l10n.bonusChallengeExercise
        case .unknown: nil
        }
    }

    /// "O'rtacha", or "Qiyin · Siz tasdiqlaysiz" when nothing can measure it.
    static func subtitle(_ challenge: BonusChallenge, _ l10n: L10n) -> String? {
        let hardness: String?
        switch challenge.difficulty {
        case .easy: hardness = l10n.bonusChallengeEasy
        case .medium: hardness = l10n.bonusChallengeMedium
        case .hard: hardness = l10n.bonusChallengeHard
        case .unknown: hardness = nil
        }
        guard let hardness else { return nil }
        return challenge.requiresParentApproval ? l10n.bonusChallengeSubtitle(hardness) : hardness
    }

    static func minutes(_ challenge: BonusChallenge, _ l10n: L10n) -> String {
        l10n.bonusChallengeMinutes(Durations.short(challenge.bonusMinutes, l10n))
    }

    static func caption(childName: String?, _ l10n: L10n) -> String {
        childName.map(l10n.bonusCaptionNamed) ?? l10n.bonusCaption
    }
}
