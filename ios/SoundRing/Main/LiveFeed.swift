import Foundation

/// Where the Live screen gets its sounds. The screens only see `[SoundCue]`.
protocol CueSource {
    var cues: AsyncStream<[SoundCue]> { get }
}

/// The Figma scene, drifting slightly so the screen looks alive. Used until real data is wired in.
struct DemoCueSource: CueSource {
    var cues: AsyncStream<[SoundCue]> {
        AsyncStream { continuation in
            let task = Task {
                var t = 0.0
                while !Task.isCancelled {
                    continuation.yield(DemoData.liveScene.enumerated().map { i, cue in
                        var c = cue
                        c.azimuthDeg += sin(t * 0.8 + Double(i) * 1.7) * 4
                        return c
                    })
                    t += 0.1
                    try? await Task.sleep(for: .milliseconds(100))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
