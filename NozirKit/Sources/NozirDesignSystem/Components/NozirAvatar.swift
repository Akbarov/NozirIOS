import SwiftUI

/// Android `NozirAvatarTone`: an identity colour, never a status. `rawValue`
/// is what the server stores.
public enum AvatarTone: String, CaseIterable, Sendable {
    case teal, apricot, sky

    /// The stored key's tone; a key this app does not know falls back to a
    /// colour by list position (Android `AvatarToneForChild`).
    public static func forKey(_ key: String?, position: Int = 0) -> AvatarTone {
        if let key, let tone = AvatarTone(rawValue: key) { return tone }
        return allCases[abs(position) % allCases.count]
    }

    var container: Color {
        switch self {
        case .teal: NozirColor.primaryContainer
        case .apricot: NozirColor.apricotContainer
        case .sky: NozirColor.skyContainer
        }
    }

    var content: Color {
        switch self {
        case .teal: NozirColor.onPrimaryContainer
        case .apricot: NozirColor.apricotContent
        case .sky: NozirColor.skyContent
        }
    }
}

/// A child's initial in their colour.
public struct NozirAvatar: View {
    private let initial: String
    private let tone: AvatarTone
    private let size: CGFloat

    public init(name: String, tone: AvatarTone, fallbackInitial: String, size: CGFloat = 40) {
        initial = Self.initial(of: name, fallback: fallbackInitial)
        self.tone = tone
        self.size = size
    }

    nonisolated static func initial(of name: String, fallback: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? fallback
    }

    public var body: some View {
        Text(initial)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tone.content)
            .frame(width: size, height: size)
            .background(Circle().fill(tone.container))
            .accessibilityHidden(true)
    }
}

/// Android `AvatarChoiceRow`: the three tones, the chosen one ringed.
public struct NozirAvatarPicker: View {
    @Binding private var selection: AvatarTone
    private let name: String
    private let fallbackInitial: String
    private let accessibilityLabel: String

    public init(selection: Binding<AvatarTone>, name: String, fallbackInitial: String, accessibilityLabel: String) {
        _selection = selection
        self.name = name
        self.fallbackInitial = fallbackInitial
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        HStack(spacing: NozirSpacing.medium) {
            ForEach(Array(AvatarTone.allCases.enumerated()), id: \.element) { index, tone in
                Button {
                    selection = tone
                } label: {
                    NozirAvatar(name: name, tone: tone, fallbackInitial: fallbackInitial, size: 48)
                        .padding(4)
                        .overlay(
                            Circle().strokeBorder(
                                selection == tone ? NozirColor.primary : Color.clear,
                                lineWidth: NozirSize.borderEmphasis
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue("\(index + 1) / \(AvatarTone.allCases.count)")
                .accessibilityAddTraits(selection == tone ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}
