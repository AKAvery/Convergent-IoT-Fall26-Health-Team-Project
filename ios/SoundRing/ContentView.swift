import SwiftUI
import Models

struct ContentView: View {
    // Placeholder data built from the shared Models contract.
    private let events: [SoundEvent] = [
        SoundEvent(label: .siren, confidence: 0.92, azimuthDeg: 90, levelDb: 18,
                   startedAt: .now, updatedAt: .now, isActive: true, isUrgent: true,
                   categories: [.safety]),
        SoundEvent(label: .knock, confidence: 0.81, azimuthDeg: 270, levelDb: 9,
                   startedAt: .now, updatedAt: .now, isActive: true, isUrgent: false,
                   categories: [.privacy]),
    ]

    var body: some View {
        NavigationStack {
            List(events) { event in
                HStack {
                    VStack(alignment: .leading) {
                        Text(event.label.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.headline)
                        if let az = event.azimuthDeg {
                            Text("\(Int(az))° clockwise from ahead")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if event.isUrgent {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Sound Ring")
        }
    }
}

#Preview {
    ContentView()
}
