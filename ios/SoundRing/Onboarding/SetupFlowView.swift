import SwiftUI

enum SetupStep: Int {
    case find = 1, connect, align
}

/// Pairing: Find → Connect → Align (design-refs/Find_Glasses, Connecting_Glasses, Final_Setup).
/// Reached from Welcome ("Create an account") and Pins ("Pair New Pin").
struct SetupFlowView: View {
    var startAt: SetupStep = .find
    let onFinish: () -> Void
    let onCancel: () -> Void
    @State private var step: SetupStep?

    var body: some View {
        let current = step ?? startAt
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(step: current.rawValue) {
                switch current {
                case .find: onCancel()
                case .connect: step = .find
                case .align: step = .connect
                }
            }
            switch current {
            case .find: FindPinsStep { step = .connect }
            case .connect: ConnectingStep { step = .align }
            case .align: AlignStep(onFinish: onFinish)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.25), value: current)
    }
}

// MARK: - 1 Find

struct FindPinsStep: View {
    let onConnect: () -> Void
    @State private var found = 0          // how many of DemoData.pinsFoundNearby are listed
    @State private var scan = 0           // bump to restart the search

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find your pins").font(.largeTitle.bold())
            Text("Place your pins in close vicinity to your mobile phone.")
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            RadarSweep()
                .frame(width: 220, height: 220)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

            Text("Devices found nearby").foregroundStyle(Theme.secondaryText)
            VStack(spacing: 12) {
                ForEach(Array(DemoData.pinsFoundNearby.prefix(found).enumerated()), id: \.offset) { i, name in
                    HStack(spacing: 14) {
                        Image(systemName: "paperclip")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentDim))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.headline)
                            Text("Ready to pair").font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Button("Connect", action: onConnect)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(i == 0 ? Theme.accent : .clear))
                            .overlay(Capsule().stroke(Theme.accent))
                            .foregroundStyle(i == 0 ? Theme.background : Theme.accent)
                            .buttonStyle(.plain)
                    }
                    .padding(12)
                    .card(radius: 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            HStack(spacing: 8) {
                BluetoothGlyph()
                    .stroke(Theme.secondaryText, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    .frame(width: 10, height: 16)
                Text("Searching... make sure Bluetooth is on")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.top, 6)

            Spacer(minLength: 12)
            SecondaryButton(title: "I can\u{2019}t find my pins") { scan += 1 }
                .padding(.horizontal, 24)
        }
        .task(id: scan) {
            found = 0
            for n in 1...DemoData.pinsFoundNearby.count {
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(.spring) { found = n }
            }
        }
    }
}

/// Rings with a rotating sweep and the pin in the middle.
struct RadarSweep: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3 * 360
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    ForEach(1...4, id: \.self) { i in
                        Circle().stroke(Theme.accent.opacity(0.18), lineWidth: 1)
                            .frame(width: s * CGFloat(i) / 4, height: s * CGFloat(i) / 4)
                            .position(c)
                    }
                    Circle()
                        .trim(from: 0, to: 0.12)
                        .fill(AngularGradient(colors: [Theme.accent.opacity(0), Theme.accent.opacity(0.45)],
                                              center: .center, startAngle: .degrees(0), endAngle: .degrees(43)))
                        .frame(width: s, height: s)
                        .rotationEffect(.degrees(angle))
                        .position(c)
                    Circle().fill(Theme.accent).frame(width: 9, height: 9)
                        .position(CueDirection.point(c, s * 0.37, 50))
                    Circle().fill(Theme.accent.opacity(0.7)).frame(width: 7, height: 7)
                        .position(CueDirection.point(c, s * 0.3, 235))
                    Image(systemName: "paperclip")
                        .font(.system(size: s * 0.12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: s * 0.27, height: s * 0.27)
                        .background(Circle().fill(Theme.accentDim))
                        .overlay(Circle().stroke(Theme.accent, lineWidth: 2))
                        .shadow(color: Theme.accent.opacity(0.6), radius: 12)
                        .position(c)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 2 Connect

struct ConnectingStep: View {
    let onContinue: () -> Void
    @State private var progress = 0.0
    private let checks = [(0.25, "Checking device battery"),
                          (0.55, "Confirming device firmware"),
                          (0.85, "Authenticating connection")]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connecting...").font(.largeTitle.bold())
            Text("Linking to your Halo pins. Keep your pins close -- this takes about 30 seconds.")
                .foregroundStyle(Theme.secondaryText)

            ZStack {
                Circle().fill(Theme.surface.opacity(0.6))
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.accent.opacity(0.6), radius: 10)
                    .padding(14)
                VStack(spacing: 6) {
                    Image(systemName: "figure.stand").font(.system(size: 40)).foregroundStyle(Theme.accent)
                    Text("\(Int(progress * 100))%").font(.title.bold()).monospacedDigit()
                }
            }
            .frame(width: 210, height: 210)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

            VStack(alignment: .leading, spacing: 22) {
                Text("Bluetooth link established")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                ForEach(checks, id: \.1) { at, title in
                    HStack(spacing: 14) {
                        Circle()
                            .fill(progress >= at ? Theme.accent : .clear)
                            .overlay(Circle().stroke(progress >= at ? Theme.accent : Theme.secondaryText, lineWidth: 1.5))
                            .frame(width: 24, height: 24)
                        Text(title).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .padding(20)
            .card(radius: 18)

            Spacer(minLength: 12)
            PrimaryButton(title: "Continue to next step", action: onContinue)
        }
        .task {
            progress = 0
            while progress < 1 {
                try? await Task.sleep(for: .milliseconds(40))
                withAnimation(.linear(duration: 0.04)) { progress = min(1, progress + 0.01) }
            }
        }
    }
}

// MARK: - 3 Align

/// One quarter of the alignment ring. Order follows the design: front-right, back-right,
/// back-left, front-left.
private enum MicSide: Int, CaseIterable {
    case frontRight, backRight, backLeft, frontLeft
    var name: String { ["front right", "back right", "back left", "front left"][rawValue] }
    var azimuthDeg: Double { [45, 135, 225, 315][rawValue] }
}

struct AlignStep: View {
    let onFinish: () -> Void
    @State private var aligned = 0       // sides done, in MicSide order
    @State private var run = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aligning the microphones").font(.title.bold())
            Text("Say \u{201C}Hello\u{201D} toward each highlighted side so your pins learn where sound comes from.")
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").foregroundStyle(Theme.accent)
                Text("Find a quiet spot - background noise can reduce accuracy.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            .padding(.vertical, 10)

            AlignRing(aligned: aligned)
                .frame(width: 236, height: 236)
                .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text(aligned < 4 ? "Speak now - \(MicSide.allCases[aligned].name)" : "All microphones aligned")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.accent)
                Text("\(aligned) of 4 microphones aligned").foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)

            Spacer(minLength: 12)
            PrimaryButton(title: "Finish setup", action: onFinish)
            SecondaryButton(title: "Try alignment again") { run += 1 }
        }
        .task(id: run) {
            aligned = 0
            while aligned < 4 {
                try? await Task.sleep(for: .milliseconds(1600))
                withAnimation(.easeInOut) { aligned += 1 }
            }
        }
    }
}

private struct AlignRing: View {
    let aligned: Int
    private let green = Theme.ambient

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let ringWidth = s * 0.2
            let radius = s / 2 - ringWidth / 2
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 1).frame(width: s * 0.58, height: s * 0.58).position(c)
                ForEach(MicSide.allCases, id: \.self) { side in
                    let state = side.rawValue < aligned ? 2 : side.rawValue == aligned ? 1 : 0
                    let color = state == 2 ? green : state == 1 ? Theme.accent : Theme.surfaceRaised
                    Circle()
                        .trim(from: 0, to: 80.0 / 360)
                        .stroke(color, style: StrokeStyle(lineWidth: ringWidth))
                        .frame(width: radius * 2, height: radius * 2)
                        .rotationEffect(.degrees(side.azimuthDeg - 40 - 90))
                        .shadow(color: state > 0 ? color.opacity(0.6) : .clear, radius: 10)
                        .position(c)
                    Image(systemName: state == 2 ? "checkmark" : "mic")
                        .font(.headline)
                        .foregroundStyle(state == 1 ? Theme.background : state == 2 ? Theme.background : Theme.secondaryText)
                        .position(CueDirection.point(c, radius, side.azimuthDeg))
                }
                Image(systemName: "figure.stand")
                    .font(.system(size: s * 0.15))
                    .foregroundStyle(Theme.accent)
                    .frame(width: s * 0.32, height: s * 0.32)
                    .background(Circle().fill(Theme.surfaceRaised))
                    .position(c)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(aligned) of 4 microphones aligned")
    }
}
