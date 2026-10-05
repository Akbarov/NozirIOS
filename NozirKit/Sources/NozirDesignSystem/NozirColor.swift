import SwiftUI
import UIKit

/// One colour from a 0xRRGGBB literal, as the Android palette writes it.
struct RGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }
}

/// Android `NozirLightColors` / `NozirDarkColors`, the roles the foundation's
/// screens use. Dark containers and borders are their colour at 12% and 30%,
/// as `NozirTonalColor.onDarkSurface` draws them.
public enum NozirColor {
    public static let primary = color(light: 0x0E9F8F, dark: 0x0FA799)
    public static let onPrimary = color(light: 0xFFFFFF, dark: 0x04211E)
    public static let primaryAccent = color(light: 0x0B8478, dark: 0x2BB9A9)
    public static let primaryContainer = color(light: 0xDCF4F0, dark: 0x0B3F39)
    public static let background = color(light: 0xFBFAF8, dark: 0x141A19)
    public static let card = color(light: 0xFFFFFF, dark: 0x1F2725)
    public static let border = color(light: 0xDCE4E2, dark: 0x28322F)
    public static let divider = color(light: 0xEEF2F1, dark: 0x28322F)
    public static let track = color(light: 0xEEF2F1, dark: 0x28322F)
    public static let textPrimary = color(light: 0x0F1A19, dark: 0xE6ECEA)
    public static let textSecondary = color(light: 0x5B6B68, dark: 0x8FA5A1)
    public static let textTertiary = color(light: 0x8B9A97, dark: 0x5B6B68)
    public static let textDisabled = color(light: 0xB8C4C1, dark: 0x5B6B68)
    public static let goodContent = color(light: 0x0B7A5E, dark: 0x2BB9A9)
    public static let goodContainer = color(light: 0xE7F4EF, dark: 0x0FA799, darkAlpha: 0.12)
    public static let actionContent = color(light: 0xC2410C, dark: 0xF0803F)
    public static let criticalContent = color(light: 0xB91C1C, dark: 0xE66767)
    public static let criticalBorder = color(light: 0xF4C7C7, dark: 0xE66767, darkAlpha: 0.30)
    public static let onPrimaryContainer = color(light: 0x07695F, dark: 0x7FD6CB)
    public static let apricotContent = color(light: 0xC2500F, dark: 0xE59F7E)
    public static let apricotContainer = color(light: 0xFFF0E4, dark: 0xD95926, darkAlpha: 0.12)
    public static let skyContent = color(light: 0x2A78D6, dark: 0x3987E5)
    public static let skyContainer = color(light: 0xE8F2FF, dark: 0x3987E5, darkAlpha: 0.12)
    public static let attentionContent = color(light: 0xB87503, dark: 0xE5A63B)
    public static let attentionContainer = color(light: 0xFDF3E0, dark: 0xE5A63B, darkAlpha: 0.12)
    public static let attentionBorder = color(light: 0xF0D9A8, dark: 0xE5A63B, darkAlpha: 0.30)

    static func uiColor(light: UInt32, dark: UInt32, darkAlpha: Double = 1) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: 1)
        }
    }

    private static func color(light: UInt32, dark: UInt32, darkAlpha: Double = 1) -> Color {
        Color(uiColor: uiColor(light: light, dark: dark, darkAlpha: darkAlpha))
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double) {
        let rgb = RGB(hex: hex)
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }
}
