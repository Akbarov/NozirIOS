import SwiftUI

/// Android `NozirLogoMark`: a teal tile with an open ring and a light tail.
/// Arc angles match Compose's (0° at three o'clock, clockwise).
public struct NozirLogoMark: View {
    private let label: String

    public init(accessibilityLabel: String) {
        label = accessibilityLabel
    }

    public var body: some View {
        let ring = NozirSize.logoRing - NozirSize.logoStroke
        RoundedRectangle(cornerRadius: NozirRadius.logo)
            .fill(NozirColor.primary)
            .frame(width: NozirSize.logo, height: NozirSize.logo)
            .overlay {
                ZStack {
                    Circle()
                        .trim(from: 0.125, to: 0.875)
                        .stroke(NozirColor.onPrimary, lineWidth: NozirSize.logoStroke)
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(NozirColor.primaryContainer, lineWidth: NozirSize.logoStroke)
                        .rotationEffect(.degrees(315))
                }
                .frame(width: ring, height: ring)
            }
            .accessibilityElement()
            .accessibilityLabel(label)
    }
}
