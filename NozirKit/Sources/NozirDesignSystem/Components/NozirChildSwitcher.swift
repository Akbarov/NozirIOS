import SwiftUI

public struct NozirSwitcherChild: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let tone: AvatarTone
    public let needsAttention: Bool

    public init(id: UUID, name: String, tone: AvatarTone, needsAttention: Bool = false) {
        self.id = id
        self.name = name
        self.tone = tone
        self.needsAttention = needsAttention
    }
}

/// Android `ChildAvatarSwitcher`: the children's faces in a row. With
/// `allTitle` there is an "everyone" chip first (P05); without it one child is
/// always chosen (Statistics). `addTitle` + `onAdd` end the row with "+".
public struct NozirChildSwitcher: View {
    private let children: [NozirSwitcherChild]
    @Binding private var selection: UUID?
    private let allTitle: String?
    private let allAccessibilityLabel: String?
    private let addTitle: String?
    private let onAdd: (() -> Void)?
    private let fallbackInitial: String

    public init(
        children: [NozirSwitcherChild],
        selection: Binding<UUID?>,
        allTitle: String? = nil,
        allAccessibilityLabel: String? = nil,
        addTitle: String? = nil,
        onAdd: (() -> Void)? = nil,
        fallbackInitial: String
    ) {
        self.children = children
        _selection = selection
        self.allTitle = allTitle
        self.allAccessibilityLabel = allAccessibilityLabel
        self.addTitle = addTitle
        self.onAdd = onAdd
        self.fallbackInitial = fallbackInitial
    }

    /// The choice after a tap. `nil` tapped is the "everyone" chip.
    nonisolated static func selection(afterTapping tapped: UUID?, current: UUID?, allowsAll: Bool) -> UUID? {
        guard let tapped else { return nil }
        if allowsAll, tapped == current { return nil }
        return tapped
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: NozirSpacing.compact) {
                if let allTitle {
                    chip(isSelected: selection == nil, label: allTitle, accessibility: allAccessibilityLabel ?? allTitle) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(NozirColor.onPrimaryContainer)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(NozirColor.primaryContainer))
                    } action: {
                        selection = Self.selection(afterTapping: nil, current: selection, allowsAll: true)
                    }
                }
                ForEach(children) { child in
                    chip(isSelected: selection == child.id, label: child.name, accessibility: child.name) {
                        NozirAvatar(name: child.name, tone: child.tone, fallbackInitial: fallbackInitial, size: 44)
                            .overlay(alignment: .topTrailing) {
                                if child.needsAttention {
                                    Circle()
                                        .fill(NozirColor.actionContent)
                                        .frame(width: 10, height: 10)
                                        .accessibilityHidden(true)
                                }
                            }
                    } action: {
                        selection = Self.selection(afterTapping: child.id, current: selection, allowsAll: allTitle != nil)
                    }
                }
                if let addTitle, let onAdd {
                    chip(isSelected: false, label: addTitle, accessibility: addTitle) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(NozirColor.primaryAccent)
                            .frame(width: 44, height: 44)
                            .overlay(Circle().strokeBorder(NozirColor.border, lineWidth: NozirSize.borderResting))
                    } action: {
                        onAdd()
                    }
                }
            }
            .padding(.vertical, NozirSpacing.extraSmall)
        }
    }

    private func chip<Face: View>(
        isSelected: Bool,
        label: String,
        accessibility: String,
        @ViewBuilder face: () -> Face,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: NozirSpacing.extraSmall) {
                face()
                    .padding(3)
                    .overlay(
                        Circle().strokeBorder(isSelected ? NozirColor.primary : .clear, lineWidth: NozirSize.borderEmphasis)
                    )
                Text(label)
                    .nozirText(.label, color: isSelected ? NozirColor.textPrimary : NozirColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
