import CoreGraphics

/// Android `NozirSpacing` at the reference width.
public enum NozirSpacing {
    public static let extraSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let compact: CGFloat = 12
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 20
    public static let extraLarge: CGFloat = 24
    public static let section: CGFloat = 32
}

/// Android `NozirShapes` corner radii.
public enum NozirRadius {
    public static let cardCompact: CGFloat = 12
    public static let field: CGFloat = 12
    public static let button: CGFloat = 11
    public static let logo: CGFloat = 17
}

/// Android `NozirSizing` and component constants.
public enum NozirSize {
    public static let buttonCallToAction: CGFloat = 52
    public static let buttonStandard: CGFloat = 48
    public static let control: CGFloat = 52
    public static let icon: CGFloat = 24
    public static let logo: CGFloat = 56
    public static let logoRing: CGFloat = 24
    public static let logoStroke: CGFloat = 4
    public static let borderResting: CGFloat = 1.5
    public static let borderEmphasis: CGFloat = 2
}
