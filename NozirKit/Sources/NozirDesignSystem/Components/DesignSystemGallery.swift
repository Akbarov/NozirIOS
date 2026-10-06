import SwiftUI

#Preview("Nozir components") {
    ScrollView {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            NozirLogoMark(accessibilityLabel: "Nozir")
            Text("Headline").nozirText(.headline)
            Text("Body text").nozirText(.body, color: NozirColor.textSecondary)
            NozirButton("Primary", size: .callToAction) {}
            NozirButton("Loading", isLoading: true) {}
            NozirButton("Secondary", variant: .secondary) {}
            NozirButton("Ghost", variant: .ghost) {}
            NozirButton("Critical", variant: .criticalOutline) {}
            NozirButton("Disabled", variant: .secondary) {}.disabled(true)
            NozirBulletRow("Bullet row")
            NozirInlineMessage("Inline message")
            NozirPrivacyNote("Privacy note")
            NozirCodeField(code: .constant(""), placeholder: "000000")
        }
        .padding(NozirSpacing.medium)
    }
    .background(NozirColor.background)
}

#Preview("Nozir toast") {
    NozirColor.background
        .ignoresSafeArea()
        .nozirToast(.constant("The app that does this was not found"))
}
