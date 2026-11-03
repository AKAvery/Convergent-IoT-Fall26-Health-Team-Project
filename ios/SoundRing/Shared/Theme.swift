import SwiftUI

// Colours from the Figma screens in ios/design-refs/. The app is dark-only.
// Shared by the iPhone app and the Watch app.
enum Theme {
    static let background = Color(red: 0.035, green: 0.051, blue: 0.086)
    static let surface = Color(red: 0.086, green: 0.114, blue: 0.169)
    static let surfaceRaised = Color(red: 0.118, green: 0.149, blue: 0.212)
    static let line = Color.white.opacity(0.14)
    static let secondaryText = Color(red: 0.62, green: 0.67, blue: 0.75)
    static let accent = Color(red: 0.13, green: 0.83, blue: 0.93)
    static let accentDim = Color(red: 0.07, green: 0.25, blue: 0.29)

    static let urgent = Color(red: 1.00, green: 0.33, blue: 0.42)
    static let traffic = Color(red: 1.00, green: 0.71, blue: 0.20)
    static let speech = Color(red: 0.66, green: 0.56, blue: 1.00)
    static let ambient = Color(red: 0.20, green: 0.78, blue: 0.55)
}
