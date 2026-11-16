import SwiftUI
#if os(iOS)
import UIKit
#endif

// The one place colours, spacing and corner radii are defined. Shared by the iPhone app and the
// Watch app. The iPhone app follows the system appearance; the Watch is always dark.
//
// Rules:
// - `accent` is for primary actions and the current selection only. Never decoration.
// - The four sound-group colours (`urgent`, `traffic`, `speech`, `ambient`) carry information:
//   they mean "this is that kind of sound". Don't reuse them for status (done, online, battery OK).
// - Every text colour here is at least 4.5:1 against `background` and `surface` in both modes.
enum Theme {
    // MARK: Neutrals (the iOS grouped greys, so screens sit next to Settings and Health)

    /// Screen background. Light grey in light mode, black in dark (black on the Watch).
    static let background = adaptive(light: 0xF2F2F7, dark: 0x000000)
    /// Rows in grouped lists and the few panels that need a surface.
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// Quiet fills: secondary buttons, empty segments, slider tracks.
    static let fill = adaptive(light: 0xE5E5EA, dark: 0x2C2C2E)
    /// Hairlines and separators.
    static let line = adaptive(light: 0x3C3C43, dark: 0x545458, lightAlpha: 0.29, darkAlpha: 0.6)
    static let text = adaptive(light: 0x000000, dark: 0xFFFFFF)
    static let secondaryText = adaptive(light: 0x6C6C70, dark: 0x98989F)

    // MARK: Accent (primary actions and selection only)

    /// A plain system-style blue, darkened in light mode so white button text passes AA.
    static let accent = adaptive(light: 0x0064D2, dark: 0x64A8FF)
    /// Text and icons drawn on top of `accent` or a sound-group colour.
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x000000)
    /// A pale wash of the accent: behind the dial's centre mark and the profile button.
    static let accentDim = adaptive(light: 0xDCE9F8, dark: 0x16294A)

    // MARK: Sound groups (information, not decoration)
    // Based on the system red, orange, purple and green, using their high-contrast variants.

    static let urgent = adaptive(light: 0xD70015, dark: 0xFF6961)
    static let traffic = adaptive(light: 0xA35A00, dark: 0xFFB340)
    static let speech = adaptive(light: 0x8944AB, dark: 0xD08BEF)
    static let ambient = adaptive(light: 0x1F7A37, dark: 0x30DB5B)

    // MARK: Profile themes (Profile > Edit). Muted on purpose and separate from the sound colours.

    static let profileThemes: [(name: String, color: Color)] = [
        ("Midnight", adaptive(light: 0x2C2C2E, dark: 0x3A3A3C)),
        ("Forest", adaptive(light: 0x3D6B4F, dark: 0x4C7D5F)),
        ("Aurora", adaptive(light: 0x4F6A85, dark: 0x5F7B97)),
        ("Dusk", adaptive(light: 0x9A5444, dark: 0xAD6655)),
    ]

    // MARK: Spacing and radii

    /// 4-point steps. Use small steps inside a group and `xl` between groups, so the gaps
    /// themselves show what belongs together.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 20
        static let xl: CGFloat = 32
        /// Left and right screen margin.
        static let margin: CGFloat = 20
    }

    enum Radius {
        /// Buttons and the dial panel.
        static let control: CGFloat = 12
        /// Sound chips on the dial.
        static let chip: CGFloat = 8
    }

    // MARK: -

    private static func adaptive(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        #if os(iOS)
        Color(UIColor { traits in
            let (hex, a) = traits.userInterfaceStyle == .dark ? (dark, darkAlpha) : (light, lightAlpha)
            let c = rgb(hex)
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: a)
        })
        #else
        let c = rgb(dark)
        return Color(red: c.0, green: c.1, blue: c.2).opacity(darkAlpha)
        #endif
    }

    private static func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}
