import SwiftUI

/// Android `SavingBadge`: a small solid pill that sits on a card's top edge
/// ("38% tejaysiz"). Decoration that also says something, so it is read.
public struct NozirBadge: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .nozirText(.label, color: NozirColor.onAccentSolid)
            .padding(.horizontal, 11)
            .padding(.vertical, NozirSpacing.extraSmall)
            .background(Capsule().fill(NozirColor.accentSolid))
    }
}
