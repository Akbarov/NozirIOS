import SwiftUI
import Testing
import UIKit
@testable import NozirDesignSystem

private func components(_ color: Color, _ style: UIUserInterfaceStyle) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    UIColor(color)
        .resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (red, green, blue, alpha)
}

/// The colour is `light` opaque in light mode and `dark` at `darkAlpha` in dark mode.
private func isTonal(_ color: Color, light: UInt32, dark: UInt32, darkAlpha: CGFloat) -> Bool {
    let day = components(color, .light)
    let night = components(color, .dark)
    let lightRGB = RGB(hex: light)
    let darkRGB = RGB(hex: dark)
    return abs(day.red - CGFloat(lightRGB.red)) < 0.002
        && abs(day.green - CGFloat(lightRGB.green)) < 0.002
        && abs(day.blue - CGFloat(lightRGB.blue)) < 0.002
        && abs(day.alpha - 1) < 0.002
        && abs(night.red - CGFloat(darkRGB.red)) < 0.002
        && abs(night.green - CGFloat(darkRGB.green)) < 0.002
        && abs(night.blue - CGFloat(darkRGB.blue)) < 0.002
        && abs(night.alpha - darkAlpha) < 0.002
}

@MainActor
@Suite struct CardToneTests {
    // Android `NozirLightColors` / `NozirDarkColors`: teal, statusGood, info, accentSolid.
    @Test func theP19ColoursAreAndroidsTonalColours() {
        #expect(isTonal(NozirColor.tealContainer, light: 0xEEFAF8, dark: 0x0FA799, darkAlpha: 0.12))
        #expect(isTonal(NozirColor.tealBorder, light: 0xB5E8E1, dark: 0x0FA799, darkAlpha: 0.30))
        #expect(isTonal(NozirColor.goodBorder, light: 0xBFE6DD, dark: 0x0FA799, darkAlpha: 0.30))
        #expect(isTonal(NozirColor.skyBorder, light: 0xC3DFFD, dark: 0x3987E5, darkAlpha: 0.30))
        #expect(isTonal(NozirColor.accentSolid, light: 0xFF8A3D, dark: 0xD95926, darkAlpha: 1))
        #expect(isTonal(NozirColor.onAccentSolid, light: 0x3A1C06, dark: 0xFFFFFF, darkAlpha: 1))
    }

    // Android `NozirCard`: each tone is its tonal colour's container and border.
    @Test func eachToneDrawsItsOwnFillAndBorder() {
        #expect(NozirCardTone.plain.fill == NozirColor.card)
        #expect(NozirCardTone.plain.border == NozirColor.border)
        #expect(NozirCardTone.attention.fill == NozirColor.attentionContainer)
        #expect(NozirCardTone.attention.border == NozirColor.attentionBorder)
        #expect(NozirCardTone.critical.fill == NozirColor.criticalContainer)
        #expect(NozirCardTone.critical.border == NozirColor.criticalBorder)
        #expect(NozirCardTone.selected.fill == NozirColor.tealContainer)
        #expect(NozirCardTone.selected.border == NozirColor.tealBorder)
        #expect(NozirCardTone.good.fill == NozirColor.goodContainer)
        #expect(NozirCardTone.good.border == NozirColor.goodBorder)
        #expect(NozirCardTone.info.fill == NozirColor.skyContainer)
        #expect(NozirCardTone.info.border == NozirColor.skyBorder)
    }
}
