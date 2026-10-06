import SwiftUI

/// A short message that floats above the bottom safe area, then goes away by itself.
///
/// Drive it with `.nozirToast($text)`: a non-nil text shows the toast, three
/// seconds later (or on a tap) the binding is set back to nil.
private struct NozirToastModifier: ViewModifier {
    @Binding var text: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let visibleFor: Duration = .seconds(3)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let text {
                    toast(text)
                        .padding(.horizontal, NozirSpacing.medium)
                        .padding(.bottom, NozirSpacing.medium)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: text)
            // Keyed on the text: a new message cancels this task and starts a fresh
            // three seconds; the sleep throws when cancelled, so a stale timer never
            // clears a newer message.
            .task(id: text) {
                guard let shown = text else { return }
                AccessibilityNotification.Announcement(shown).post()
                do {
                    try await Task.sleep(for: Self.visibleFor)
                } catch {
                    return
                }
                if text == shown { text = nil }
            }
    }

    private func toast(_ message: String) -> some View {
        Text(message)
            .nozirText(.bodySmall, color: NozirColor.background)
            .multilineTextAlignment(.center)
            .padding(.horizontal, NozirSpacing.medium)
            .padding(.vertical, NozirSpacing.compact)
            .background(Capsule().fill(NozirColor.textPrimary))
            .onTapGesture { text = nil }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }
}

extension View {
    /// Shows `text` as a toast while it is non-nil; see `NozirToastModifier`.
    public func nozirToast(_ text: Binding<String?>) -> some View {
        modifier(NozirToastModifier(text: text))
    }
}
