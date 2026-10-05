import Testing
import UIKit
@testable import NozirDesignSystem

private func components(_ color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (red, green, blue, alpha)
}

@MainActor
@Suite struct NozirColorTests {
    @Test func aHexLiteralBecomesItsSRGBComponents() {
        let rgb = RGB(hex: 0x0E9F8F)
        #expect(abs(rgb.red - 14.0 / 255) < 0.0001)
        #expect(abs(rgb.green - 159.0 / 255) < 0.0001)
        #expect(abs(rgb.blue - 143.0 / 255) < 0.0001)
    }

    // NozirTonalColor.onDarkSurface: a dark container is its colour at 12%.
    @Test func darkModeUsesTheDarkValueWithItsAlpha() {
        let color = NozirColor.uiColor(light: 0xE7F4EF, dark: 0x0FA799, darkAlpha: 0.12)
        let dark = components(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
        #expect(abs(dark.red - CGFloat(0x0F) / 255) < 0.001)
        #expect(abs(dark.green - CGFloat(0xA7) / 255) < 0.001)
        #expect(abs(dark.blue - CGFloat(0x99) / 255) < 0.001)
        #expect(abs(dark.alpha - 0.12) < 0.001)
    }

    @Test func lightModeUsesTheLightValueOpaque() {
        let color = NozirColor.uiColor(light: 0xE7F4EF, dark: 0x0FA799, darkAlpha: 0.12)
        let light = components(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
        #expect(abs(light.red - CGFloat(0xE7) / 255) < 0.001)
        #expect(abs(light.alpha - 1) < 0.001)
    }
}
