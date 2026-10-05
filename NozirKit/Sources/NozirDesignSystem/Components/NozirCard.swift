import SwiftUI

public enum NozirCardTone: Sendable {
    case plain, attention
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
                .fill(tone == .attention ? NozirColor.attentionContainer : NozirColor.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NozirRadius.cardCompact)
                .strokeBorder(tone == .attention ? NozirColor.attentionBorder : NozirColor.border, lineWidth: NozirSize.borderResting)
        )
    }
}
