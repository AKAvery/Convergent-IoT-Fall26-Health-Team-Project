// Angle convention (everyone uses this): 0° = straight ahead, clockwise positive,
// 90° = right, 180° = behind, 270° = left. Degrees as Float, like SoundEvent.azimuthDeg.

public enum Azimuth {
    /// Wraps any angle into [0, 360).
    public static func normalized(_ deg: Float) -> Float {
        let r = deg.truncatingRemainder(dividingBy: 360)
        let wrapped = r < 0 ? r + 360 : r
        return wrapped == 360 ? 0 : wrapped   // guards -0.000001 + 360 rounding to 360
    }

    /// Smallest angle between two directions, in [0, 180].
    public static func difference(_ a: Float, _ b: Float) -> Float {
        let d = normalized(a - b)
        return d > 180 ? 360 - d : d
    }
}

extension BoxPosition {
    /// The direction this box faces, in the convention above.
    public var facingDeg: Float {
        switch self {
        case .front: 0
        case .right: 90
        case .back: 180
        case .left: 270
        }
    }
}
