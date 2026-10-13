import SwiftUI

public enum NozirCardTone: Sendable {
    case plain, attention, critical
    /// Android `TEAL`: a chosen option, e.g. the selected plan.
    case selected
    /// Android `GOOD`: something that works, e.g. "Nozir PRO faol".
    case good
    /// Android `INFO`: a calm note, e.g. a plan lock.
    case info

    var fill: Color {
        switch self {
        case .plain: NozirColor.card
        case .attention: NozirColor.attentionContainer
        case .critical: NozirColor.criticalContainer
        case .selected: NozirColor.tealContainer
        case .good: NozirColor.goodContainer
        case .info: NozirColor.skyContainer
        }
    }

    var border: Color {
        switch self {
        case .plain: NozirColor.border
        case .attention: NozirColor.attentionBorder
        case .critical: NozirColor.criticalBorder
        case .selected: NozirColor.tealBorder
        case .good: NozirColor.goodBorder
        case .info: NozirColor.skyBorder
        }
    }
}

/// Android `NozirCard`: a rounded surface with a hairline border.
public struct NozirCard<Content: View>: View {
    private let tone: NozirCardTone
    private let content: Content

    public init(tone: NozirCardTone = .plain, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.compact) {
            content
        }
        .padding(NozirSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NozirRadius.cardCompact)
                .fill(tone.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NozirRadius.cardCompact)
                .strokeBorder(tone.border, lineWidth: NozirSize.borderResting)
        )
    }
}
