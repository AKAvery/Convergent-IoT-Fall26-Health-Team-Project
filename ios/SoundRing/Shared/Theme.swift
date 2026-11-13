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
    // MARK: Neutrals (warm, not navy)

    /// Screen background. Off-white in light mode, neutral near-black in dark.
    static let background = adaptive(light: 0xF5F4F1, dark: 0x111112)
    /// Rows in grouped lists and the few panels that need a surface.
    static let surface = adaptive(light: 0xFDFCFB, dark: 0x1E1E20)
    /// Quiet fills: secondary buttons, empty segments, slider tracks.
    static let fill = adaptive(light: 0xEAE8E4, dark: 0x2A2A2C)
    /// Hairlines and separators.
    static let line = adaptive(light: 0x1C1B19, dark: 0xFFFFFF, lightAlpha: 0.12, darkAlpha: 0.12)
    static let text = adaptive(light: 0x1C1B19, dark: 0xF2F1EE)
    static let secondaryText = adaptive(light: 0x64625E, dark: 0xA1A09C)

    // MARK: Accent (primary actions and selection only)

    static let accent = adaptive(light: 0x1B5794, dark: 0x7AAAE6)
    /// Text and icons drawn on top of `accent` or a sound-group colour.
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x111112)

    // MARK: Sound groups (information, not decoration)

    static let urgent = adaptive(light: 0xC41C2A, dark: 0xFF6A6A)
    static let traffic = adaptive(light: 0x995C00, dark: 0xF5B245)
    static let speech = adaptive(light: 0x654DC2, dark: 0xB29DFF)
    static let ambient = adaptive(light: 0x197A4D, dark: 0x61C78E)

    // MARK: Profile themes (Profile > Edit). Muted on purpose and separate from the sound colours.

    static let profileThemes: [(name: String, color: Color)] = [
        ("Midnight", adaptive(light: 0x2B2E36, dark: 0x3A3D46)),
        ("Forest", adaptive(light: 0x3F6B55, dark: 0x4F7D66)),
        ("Aurora", adaptive(light: 0x5E5F96, dark: 0x7072A8)),
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
