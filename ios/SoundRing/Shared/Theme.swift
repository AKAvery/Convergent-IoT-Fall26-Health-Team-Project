import SwiftUI
#if os(iOS)
import UIKit
#endif

// Colours from the Figma screens in ios/design-refs/ (dark), plus a light version of each.
// The iPhone app follows the system appearance; the Watch is always dark.
// Shared by the iPhone app and the Watch app.
enum Theme {
    static let background = adaptive(light: (0.957, 0.965, 0.980), dark: (0.035, 0.051, 0.086))
    static let surface = adaptive(light: (1.000, 1.000, 1.000), dark: (0.086, 0.114, 0.169))
    static let surfaceRaised = adaptive(light: (0.902, 0.922, 0.949), dark: (0.118, 0.149, 0.212))
    static let line = adaptive(light: (0.06, 0.09, 0.15), dark: (1, 1, 1), lightAlpha: 0.12, darkAlpha: 0.14)
    static let text = adaptive(light: (0.063, 0.090, 0.149), dark: (1, 1, 1))
    static let secondaryText = adaptive(light: (0.365, 0.420, 0.510), dark: (0.62, 0.67, 0.75))
    static let accent = adaptive(light: (0.000, 0.600, 0.718), dark: (0.13, 0.83, 0.93))
    static let accentDim = adaptive(light: (0.855, 0.957, 0.976), dark: (0.07, 0.25, 0.29))
    /// Text and icons drawn on top of `accent` (filled buttons, selected chips).
    static let onAccent = adaptive(light: (1, 1, 1), dark: (0.035, 0.051, 0.086))

    static let urgent = adaptive(light: (0.890, 0.188, 0.298), dark: (1.00, 0.33, 0.42))
    static let traffic = adaptive(light: (0.890, 0.545, 0.000), dark: (1.00, 0.71, 0.20))
    static let speech = adaptive(light: (0.427, 0.329, 0.937), dark: (0.66, 0.56, 1.00))
    static let ambient = adaptive(light: (0.094, 0.616, 0.400), dark: (0.20, 0.78, 0.55))

    private typealias RGB = (Double, Double, Double)

    private static func adaptive(light: RGB, dark: RGB, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        #if os(iOS)
        Color(UIColor { traits in
            let (c, a) = traits.userInterfaceStyle == .dark ? (dark, darkAlpha) : (light, lightAlpha)
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: a)
        })
        #else
        Color(red: dark.0, green: dark.1, blue: dark.2).opacity(darkAlpha)
        #endif
    }
}
