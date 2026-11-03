// soundring-listen: the real boxes on a Mac, through the app's own Input code (BLEBoxSource:
// CoreBluetooth, `level` parsing, `control`, ADPCM decode) and Detection's loudest-box switching.
// The Swift twin of firmware/tools/box_listen.py.
//
//   swift run soundring-listen                      # 10 s: levels + audio from the loudest box
//   swift run soundring-listen -s 30 --wav out.wav  # also save the decoded audio
//   swift run soundring-listen --no-audio
//
// macOS asks once for Bluetooth permission for the terminal app.
import Detection
import Foundation
import Input
import Models

var seconds = 10.0
var wavPath: String?
var audio = true
var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    switch a {
    case "-s", "--seconds": seconds = Double(args.next() ?? "") ?? seconds
    case "--wav": wavPath = args.next()
    case "--no-audio": audio = false
    default:
        print("usage: soundring-listen [-s SECONDS] [--wav OUT.wav] [--no-audio]")
        exit(2)
    }
}

let source = BLEBoxSource()
source.start()
let t0 = Date()
func elapsed() -> Double { Date().timeIntervalSince(t0) }

actor Log {
    var direction = DirectionTracker()
    var samples: [Int16] = []
    var frames = 0
    var lastPeak: [BoxPosition: Float] = [:]
    var switches: [(Double, BoxPosition)] = []

    func level(_ l: BoxLevel, audio: Bool) -> BoxPosition? {
        lastPeak[l.box] = l.peakDbfs
        direction.add(l, at: elapsed())
        guard audio, let box = direction.updateStreamingBox(at: elapsed()) else { return nil }
        switches.append((elapsed(), box))
        return box
    }

    func frame(_ f: SoundFrame) {
        frames += 1
        samples.append(contentsOf: f.samples)
    }

    var last = BLESnapshot()

    func line(_ s: BLESnapshot) -> String {
        last = s
        let boxes = BoxPosition.allCases.compactMap { b -> String? in
            guard let st = s.boxes[b], st.state != .notFound else { return nil }
            let peak = lastPeak[b].map { String(format: "%6.1f dBFS", $0) } ?? "   -"
            return "\(b.rawValue.uppercased()) \(st.state.rawValue)\(st.streamingAudio ? " [audio]" : "") \(peak)"
        }
        return String(format: "%5.1fs  bt %@  ", elapsed(), s.bluetooth.rawValue)
            + (boxes.isEmpty ? "(no box yet)" : boxes.joined(separator: " | ")) + "  frames \(frames)"
    }
}

let log = Log()
let levelTask = Task {
    for await l in source.levels {
        if let box = await log.level(l, audio: audio) { source.streamAudio(from: box) }
    }
}
let frameTask = Task { for await f in source.frames { await log.frame(f) } }
let statusTask = Task { for await s in source.status { print(await log.line(s)) } }

try await Task.sleep(for: .seconds(seconds))
source.stopAudio()
try await Task.sleep(for: .milliseconds(300))
source.stop()
try await Task.sleep(for: .milliseconds(300))
levelTask.cancel(); frameTask.cancel(); statusTask.cancel()

print("\n--- summary (\(String(format: "%.0f", seconds)) s) ---")
for (b, st) in await log.last.boxes.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where st.levelPackets > 0 || st.state != .notFound {
    print("\(b.rawValue.uppercased()): level \(st.levelPackets) pkts (missed \(st.levelMissed)), "
          + "audio \(st.audioPackets) pkts (missed \(st.audioMissed)), malformed \(st.malformed), MTU ok \(st.mtuOK)")
}
for (t, b) in await log.switches { print(String(format: "audio from %@ at %.1f s", b.rawValue.uppercased(), t)) }
let pcm = await log.samples
let peak = pcm.map { abs(Int32($0)) }.max() ?? 0
print("decoded audio: \(pcm.count) samples = \(String(format: "%.1f", Double(pcm.count) / 16000)) s, "
      + "peak \(String(format: "%.1f", 20 * log10(max(Double(peak), 1) / 32768))) dBFS")
if let wavPath, !pcm.isEmpty {
    try WAV.writeMono16k(pcm, to: URL(fileURLWithPath: wavPath))
    print("saved \(wavPath)")
}
