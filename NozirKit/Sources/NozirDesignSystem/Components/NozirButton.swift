import SwiftUI

public enum NozirButtonVariant: Sendable {
    case primary, secondary, ghost, criticalOutline
}

public enum NozirButtonSize: Sendable {
    case callToAction, standard

    var height: CGFloat {
        switch self {
        case .callToAction: NozirSize.buttonCallToAction
        case .standard: NozirSize.buttonStandard
        }
    }
}

/// Android `NozirButton` with its colour table (`NozirButtonVariantColors.kt`).
/// A disabled button keeps its outline, so a row of actions keeps its shape.
public struct NozirButton: View {
    private let title: String
    private let variant: NozirButtonVariant
    private let size: NozirButtonSize
    private let isLoading: Bool
    private let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: String,
        variant: NozirButtonVariant = .primary,
        size: NozirButtonSize = .standard,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.size = size
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(contentColor)
                } else {
                    Text(title)
                        .nozirText(.titleSmall, color: contentColor)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: size.height)
            .padding(.horizontal, NozirSpacing.large)
            .background(RoundedRectangle(cornerRadius: NozirRadius.button).fill(containerColor))
            .overlay(
                RoundedRectangle(cornerRadius: NozirRadius.button)
                    .strokeBorder(borderColor, lineWidth: NozirSize.borderResting)
            )
            .contentShape(RoundedRectangle(cornerRadius: NozirRadius.button))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(title)
    }

    private var containerColor: Color {
        if variant == .ghost { return .clear }
        guard isEnabled else { return NozirColor.track }
        return variant == .primary ? NozirColor.primary : NozirColor.card
    }

    private var contentColor: Color {
        guard isEnabled else { return NozirColor.textDisabled }
        switch variant {
        case .primary: return NozirColor.onPrimary
        case .secondary, .ghost: return NozirColor.primaryAccent
        case .criticalOutline: return NozirColor.criticalContent
        }
    }

    private var borderColor: Color {
        let hasOutline = variant == .secondary || variant == .criticalOutline
        guard isEnabled else { return hasOutline ? NozirColor.border : .clear }
        switch variant {
        case .secondary: return NozirColor.primary
        case .criticalOutline: return NozirColor.criticalBorder
        case .primary, .ghost: return .clear
        }
    }
}
