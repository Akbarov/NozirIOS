import SwiftUI

/// Android `NozirTypography`, the styles the foundation uses. Unlike the
/// Android `sp` values these scale with Dynamic Type, relative to the nearest
/// system style. Line height is approximated with `lineSpacing`.
public enum NozirTextStyle: Sendable {
    case headline, titleLarge, titleSmall, body, bodySmall, label

    var size: CGFloat {
        switch self {
        case .headline: 30
        case .titleLarge: 22
        case .titleSmall: 17
        case .body: 16
        case .bodySmall: 13
        case .label: 11
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .headline: 36
        case .titleLarge: 28
        case .titleSmall: 23
        case .body: 24
        case .bodySmall: 19
        case .label: 14
        }
    }

    var weight: Font.Weight {
        switch self {
        case .headline, .label: .bold
        case .titleLarge, .titleSmall: .semibold
        case .body, .bodySmall: .regular
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .headline: .title
        case .titleLarge: .title2
        case .titleSmall: .headline
        case .body: .body
        case .bodySmall: .footnote
        case .label: .caption2
        }
    }
}

struct NozirTextModifier: ViewModifier {
    let style: NozirTextStyle
    let color: Color
    @ScaledMetric private var size: CGFloat
    @ScaledMetric private var lineHeight: CGFloat

    init(style: NozirTextStyle, color: Color) {
        self.style = style
        self.color = color
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
        _lineHeight = ScaledMetric(wrappedValue: style.lineHeight, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: style.weight))
            .lineSpacing(max(0, lineHeight - size * 1.2))
            .foregroundStyle(color)
    }
}

extension View {
    public func nozirText(_ style: NozirTextStyle, color: Color = NozirColor.textPrimary) -> some View {
        modifier(NozirTextModifier(style: style, color: color))
    }
}
