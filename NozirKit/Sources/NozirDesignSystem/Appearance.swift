import Foundation
import Observation
import SwiftUI

/// Android `ThemeMode`, in the order the picker lists it.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case light, dark, system

    /// For `.preferredColorScheme`: nil follows the phone.
    public var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

/// The theme the parent chose on P21. Every colour in `NozirColor` already has
/// a light and a dark value, so the choice only has to reach the root view.
@MainActor
@Observable
public final class AppearanceStore {
    static let key = "nozir.appearance"

    public private(set) var mode: AppearanceMode
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.key).flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    public func set(_ mode: AppearanceMode) {
        self.mode = mode
        defaults.set(mode.rawValue, forKey: Self.key)
    }
}
