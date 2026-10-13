import SwiftUI

/// A placeholder block for content that is on its way (Android skeleton
/// blocks): the neutral track colour with a light band sweeping across it,
/// 1.2 s linear, forever. With Reduce Motion the block stands still. The
/// block is hidden from VoiceOver; the container carries the one label.
public struct NozirSkeletonBlock: View {
    private let height: CGFloat
    private let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeping = false

    public init(height: CGFloat, cornerRadius: CGFloat = NozirRadius.cardCompact) {
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(NozirColor.track)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.35), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: sweeping ? proxy.size.width : -proxy.size.width * 0.6)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    sweeping = true
                }
            }
            .accessibilityHidden(true)
    }
}
