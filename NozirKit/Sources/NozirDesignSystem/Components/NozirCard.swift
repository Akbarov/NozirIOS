import SwiftUI

public enum NozirCardTone: Sendable {
    case plain, attention, critical
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
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NozirRadius.cardCompact)
                .strokeBorder(border, lineWidth: NozirSize.borderResting)
        )
    }

    private var fill: Color {
        switch tone {
        case .plain: NozirColor.card
        case .attention: NozirColor.attentionContainer
        case .critical: NozirColor.criticalContainer
        }
    }

    private var border: Color {
        switch tone {
        case .plain: NozirColor.border
        case .attention: NozirColor.attentionBorder
        case .critical: NozirColor.criticalBorder
        }
    }
}
