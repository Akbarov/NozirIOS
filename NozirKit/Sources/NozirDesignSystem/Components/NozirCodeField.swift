import SwiftUI

/// The code box on P02: number pad, one-time-code autofill, focused on appear.
///
/// Keeps its own text and copies the bound value back after every edit: when
/// the owner rejects a keystroke (a 7th digit, a letter) the bound value does
/// not change, SwiftUI is told nothing, and the field would otherwise go on
/// showing text that is not the code.
public struct NozirCodeField: View {
    @Binding private var code: String
    private let placeholder: String
    @State private var text = ""
    @FocusState private var isFocused: Bool

    public init(code: Binding<String>, placeholder: String) {
        _code = code
        self.placeholder = placeholder
    }

    public var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(NozirColor.textTertiary))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($isFocused)
            .nozirText(.body)
            .padding(.horizontal, NozirSpacing.medium)
            .frame(minHeight: NozirSize.control)
            .background(RoundedRectangle(cornerRadius: NozirRadius.field).fill(NozirColor.card))
            .overlay(
                RoundedRectangle(cornerRadius: NozirRadius.field)
                    .strokeBorder(NozirColor.primary, lineWidth: NozirSize.borderEmphasis)
            )
            .onAppear {
                text = code
                isFocused = true
            }
            .onChange(of: text) { _, typed in
                code = typed
                if text != code { text = code }
            }
            .onChange(of: code) { _, kept in
                if text != kept { text = kept }
            }
    }
}
