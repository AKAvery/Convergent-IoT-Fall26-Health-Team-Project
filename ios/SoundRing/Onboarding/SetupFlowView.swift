import SwiftUI

enum SetupStep: Int {
    case find = 1, connect, align
}

/// Pairing: Find → Connect → Align (design-refs/Find_Glasses, Connecting_Glasses, Final_Setup).
/// Reached from Welcome ("Create an account") and Pins ("Pair a new pin").
struct SetupFlowView: View {
    var startAt: SetupStep = .find
    let onFinish: () -> Void
    let onCancel: () -> Void
    @State private var step: SetupStep?

    var body: some View {
        let current = step ?? startAt
        FillingScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
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
            .padding(.horizontal, Theme.Space.margin)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.m)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .animation(.easeInOut(duration: 0.25), value: current)
    }
}

/// Title and one line of explanation at the top of each setup step.
private struct StepTitle: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 1 Find

struct FindPinsStep: View {
    let onConnect: () -> Void
    @State private var found = 0          // how many of DemoData.pinsFoundNearby are listed
    @State private var scan = 0           // bump to restart the search

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(title: "Find your pins",
                      detail: "Hold your pins near this iPhone. They appear below when found.")

            SectionLabel("Found nearby")
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xs)
            ForEach(Array(DemoData.pinsFoundNearby.prefix(found).enumerated()), id: \.offset) { _, name in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.headline)
                        Text("Ready to pair").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button("Connect", action: onConnect)
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                        .accessibilityLabel("Connect \(name)")
                }
                .padding(.vertical, Theme.Space.m)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                .transition(.opacity)
            }
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                Text("Searching. Bluetooth needs to be on.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.vertical, Theme.Space.m)

            Spacer(minLength: Theme.Space.xl)
            Button("I can\u{2019}t find my pins") { scan += 1 }
                .buttonStyle(.borderless)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.bottom, Theme.Space.s)
        }
        .task(id: scan) {
            found = 0
            for n in 1...DemoData.pinsFoundNearby.count {
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(.easeOut(duration: 0.2)) { found = n }
            }
        }
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
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(title: "Connecting",
                      detail: "Linking to your pins. Keep them close; this takes about 30 seconds.")

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("\(Int(progress * 100))%")
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                ProgressView(value: progress)
                    .tint(Theme.accent)
            }
            .padding(.top, Theme.Space.xl)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Connecting")
            .accessibilityValue("\(Int(progress * 100)) percent")

            SectionLabel("Bluetooth link established")
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.m)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                ForEach(checks, id: \.1) { at, title in
                    let done = progress >= at
                    Label {
                        Text(title).foregroundStyle(done ? Theme.text : Theme.secondaryText)
                    } icon: {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? Theme.accent : Theme.secondaryText)
                    }
                    .accessibilityValue(done ? "Done" : "Waiting")
                }
            }

            Spacer(minLength: Theme.Space.xl)
            PrimaryButton(title: "Continue to next step", action: onContinue)
        }
        .task {
            progress = 0
            while progress < 1 {
                try? await Task.sleep(for: .milliseconds(40))
                progress = min(1, progress + 0.01)
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
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(title: "Align the microphones",
                      detail: "Turn toward each highlighted side and say \u{201C}Hello\u{201D} so your pins learn where sound comes from.")
            Label("Find a quiet spot. Background noise lowers accuracy.", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, Theme.Space.m)

            AlignRing(aligned: aligned)
                .frame(maxWidth: 240)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.xl)

            VStack(spacing: Theme.Space.xs) {
                Text(aligned < 4 ? "Speak now: \(MicSide.allCases[aligned].name)" : "All microphones aligned")
                    .font(.title3.weight(.semibold))
                Text("\(aligned) of 4 microphones aligned")
                    .foregroundStyle(Theme.secondaryText)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            Spacer(minLength: Theme.Space.xl)
            PrimaryButton(title: "Finish setup", action: onFinish)
            Button("Try alignment again") { run += 1 }
                .buttonStyle(.borderless)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Space.m)
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

/// Four segments around the wearer: the side to speak toward is in the accent colour, finished
/// sides are a light grey with a check, the rest are faint.
private struct AlignRing: View {
    let aligned: Int

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let ringWidth = s * 0.16
            let radius = s / 2 - ringWidth / 2
            ZStack {
                ForEach(MicSide.allCases, id: \.self) { side in
                    let state = side.rawValue < aligned ? 2 : side.rawValue == aligned ? 1 : 0
                    let color: Color = state == 2 ? Theme.secondaryText.opacity(0.35) : state == 1 ? Theme.accent : Theme.fill
                    let iconColor: Color = state == 2 ? Theme.text : state == 1 ? Theme.onAccent : Theme.secondaryText
                    Circle()
                        .trim(from: 0, to: 80.0 / 360)
                        .stroke(color, style: StrokeStyle(lineWidth: ringWidth))
                        .frame(width: radius * 2, height: radius * 2)
                        .rotationEffect(.degrees(side.azimuthDeg - 40 - 90))
                        .position(c)
                    Image(systemName: state == 2 ? "checkmark" : "mic")
                        .font(.headline)
                        .foregroundStyle(iconColor)
                        .position(CueDirection.point(c, radius, side.azimuthDeg))
                }
                Image(systemName: "figure.stand")
                    .font(.system(size: s * 0.16))
                    .foregroundStyle(Theme.text)
                    .position(c)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(aligned) of 4 microphones aligned")
    }
}
