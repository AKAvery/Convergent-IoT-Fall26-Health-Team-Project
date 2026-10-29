import Foundation
import Testing
@testable import Models

/// Repo root, found from this file: ios/Packages/SoundRingKit/Tests/ModelsTests/<file>.
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // ModelsTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // SoundRingKit
    .deletingLastPathComponent()   // Packages
    .deletingLastPathComponent()   // ios
    .deletingLastPathComponent()   // repo root

private func modelLabels() throws -> [String] {
    let url = repoRoot.appendingPathComponent("ml/models/labels.json")
    return try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
}

@Suite struct SoundLabelTests {
    /// Every model class except `other` is a SoundLabel, spelled exactly as in labels.json.
    @Test func casesMatchLabelsJSON() throws {
        let labels = try modelLabels()
        #expect(labels.count == Set(labels).count, "labels.json has duplicates")
        let expected = Set(labels).subtracting(["other"])
        let actual = Set(SoundLabel.allCases.map(\.rawValue))
        #expect(actual == expected)
        #expect(SoundLabel.allCases.count == labels.count - 1)
    }

    @Test func otherIsNotAnEventLabel() {
        #expect(SoundLabel(rawValue: "other") == nil)
    }

    @Test func snakeCaseRawValues() {
        #expect(SoundLabel.glassBreak.rawValue == "glass_break")
        #expect(SoundLabel.carHorn.rawValue == "car_horn")
        #expect(SoundLabel.babyCry.rawValue == "baby_cry")
    }

    @Test func soundEventCodableRoundTrip() throws {
        let event = SoundEvent(
            label: .glassBreak, confidence: 0.8, azimuthDeg: 270, levelDb: 18.5,
            startedAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_002),
            isActive: true, isUrgent: true, categories: [.safety])
        let json = try JSONEncoder().encode(event)
        #expect(String(decoding: json, as: UTF8.self).contains("\"glass_break\""))
        let back = try JSONDecoder().decode(SoundEvent.self, from: json)
        #expect(back.id == event.id)
        #expect(back.label == .glassBreak)
        #expect(back.azimuthDeg == 270)
        #expect(back.categories == [.safety])
        #expect(back.updatedAt == event.updatedAt)
    }

    @Test func nilAzimuthRoundTrips() throws {
        let event = SoundEvent(
            label: .speech, confidence: 0.6, azimuthDeg: nil, levelDb: 3,
            startedAt: .now, updatedAt: .now, isActive: false, isUrgent: false, categories: [])
        let back = try JSONDecoder().decode(SoundEvent.self, from: JSONEncoder().encode(event))
        #expect(back.azimuthDeg == nil)
    }
}
