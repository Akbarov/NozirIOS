import SwiftUI
import UIKit

/// A labelled text field whose owner may refuse a keystroke (a fifth year
/// digit, a 41st letter). Like `NozirCodeField` it keeps its own text and copies
/// the owner's value back after every edit, so what is shown is what is kept.
public struct NozirTextField: View {
    private let label: String
    @Binding private var value: String
    private let placeholder: String
    private let error: String?
    private let keyboard: UIKeyboardType
    @State private var text = ""

    public init(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        error: String? = nil,
        keyboard: UIKeyboardType = .default
    ) {
        self.label = label
        _value = text
        self.placeholder = placeholder
        self.error = error
        self.keyboard = keyboard
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.small) {
            Text(label).nozirText(.bodySmall, color: NozirColor.textSecondary)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(NozirColor.textTertiary))
                .keyboardType(keyboard)
                .nozirText(.body)
                .fieldFrame(hasError: error != nil)
                .accessibilityLabel(label)
            if let error {
                NozirInlineMessage(error)
            }
        }
        .onAppear { text = value }
        .onChange(of: text) { _, typed in
            value = typed
            if text != value { text = value }
        }
        .onChange(of: value) { _, kept in
            if text != kept { text = kept }
        }
    }
}

/// Android `NozirPhoneField`: a fixed "🇺🇿 +998" prefix and nine digits shown
/// as "90 123 45 67". The binding holds the digits only.
public struct NozirPhoneField: View {
    private let label: String
    @Binding private var digits: String
    private let prefix: String
    private let placeholder: String
    private let error: String?
    @State private var text = ""

    public init(_ label: String, digits: Binding<String>, prefix: String, placeholder: String, error: String? = nil) {
        self.label = label
        _digits = digits
        self.prefix = prefix
        self.placeholder = placeholder
        self.error = error
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.small) {
            Text(label).nozirText(.bodySmall, color: NozirColor.textSecondary)
            HStack(spacing: NozirSpacing.small) {
                Text(prefix).nozirText(.body, color: NozirColor.textSecondary)
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(NozirColor.textTertiary))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .nozirText(.body)
                    .accessibilityLabel(label)
            }
            .fieldFrame(hasError: error != nil)
            if let error {
                NozirInlineMessage(error)
            }
        }
        .onAppear { text = UzbekPhone.grouped(digits) }
        .onChange(of: text) { _, typed in
            let kept = UzbekPhone.digits(from: typed)
            if digits != kept { digits = kept }
            let shown = UzbekPhone.grouped(digits)
            if text != shown { text = shown }
        }
        .onChange(of: digits) { _, kept in
            let shown = UzbekPhone.grouped(kept)
            if text != shown { text = shown }
        }
    }
}

extension View {
    /// The box every Nozir field sits in; the border turns orange with an error.
    func fieldFrame(hasError: Bool) -> some View {
        padding(.horizontal, NozirSpacing.medium)
            .frame(minHeight: NozirSize.control)
            .background(RoundedRectangle(cornerRadius: NozirRadius.field).fill(NozirColor.card))
            .overlay(
                RoundedRectangle(cornerRadius: NozirRadius.field)
                    .strokeBorder(hasError ? NozirColor.actionContent : NozirColor.border, lineWidth: NozirSize.borderResting)
            )
    }
}
