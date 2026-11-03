@preconcurrency import CoreBluetooth
import Foundation
import Models

// The iPhone side of contract 1 (docs/team-plan.md): finds the 4 boxes, keeps them connected,
// turns `level` and `audio` notifications into `BoxLevel`s and decoded `SoundFrame`s, and writes
// `control` so only the box Detection asks for streams audio.

/// UUIDs from firmware/include/box_config.h. Change only together with the firmware.
public enum SoundBoxUUID {
    public static let service = CBUUID(string: "f36b9eba-c1e3-4a55-a725-f566c01a5bdf")
    public static let level = CBUUID(string: "e89a434d-2aa6-4a70-ae89-a47761df7c97")
    public static let audio = CBUUID(string: "a6c379f3-83f3-4927-be5c-ae2966376ec4")
    public static let control = CBUUID(string: "f2b50bb3-d6c1-46a0-b5cf-ff3b5a2396f0")
}

public enum BluetoothAvailability: String, Sendable {
    case unknown, poweredOn, poweredOff, unauthorized, unsupported, resetting
}

public enum BoxLinkState: String, Sendable {
    case notFound, connecting, connected
}

/// What the app shows per box, and what the pocket test logs.
public struct BoxLinkStatus: Sendable, Equatable {
    public var state: BoxLinkState = .notFound
    public var streamingAudio = false
    public var lastPeakDbfs: Float?
    public var levelPackets = 0
    public var levelMissed = 0
    public var audioPackets = 0
    public var audioMissed = 0
    public var malformed = 0
    /// False when the negotiated MTU can't carry a 169-byte `audio` notification.
    public var mtuOK = true
    public var lowBattery = false

    public init() {}
}

public struct BLESnapshot: Sendable, Equatable {
    public var bluetooth: BluetoothAvailability = .unknown
    public var boxes: [BoxPosition: BoxLinkStatus] = [:]

    public init() {}
}

public final class BLEBoxSource: NSObject, BoxSource, @unchecked Sendable {
    public let levels: AsyncStream<BoxLevel>
    public let frames: AsyncStream<SoundFrame>
    /// A full snapshot on every connection change, and once a second while connected.
    public let status: AsyncStream<BLESnapshot>

    private let levelOut: AsyncStream<BoxLevel>.Continuation
    private let frameOut: AsyncStream<SoundFrame>.Continuation
    private let statusOut: AsyncStream<BLESnapshot>.Continuation

    // Everything below is only touched on `queue` (CoreBluetooth calls the delegate there too).
    private let queue = DispatchQueue(label: "SoundRing.BLEBoxSource")
    private var central: CBCentralManager?
    private var running = false
    private var peripherals: [BoxPosition: CBPeripheral] = [:]
    private var boxByID: [UUID: BoxPosition] = [:]
    private var unnamed: [UUID: CBPeripheral] = [:]   // connecting to learn the name
    private var control: [BoxPosition: CBCharacteristic] = [:]
    private var audioReady: Set<BoxPosition> = []
    private var wantedAudioBox: BoxPosition?
    private var lastLevelSeq: [BoxPosition: UInt16] = [:]
    private var lastAudioSeq: [BoxPosition: UInt16] = [:]
    private var snapshot = BLESnapshot()
    private var ticker: DispatchSourceTimer?
    private let restoreIdentifier: String?

    /// `restoreIdentifier`: set it in the app so iOS can relaunch it for BLE events in the
    /// background (`bluetooth-central`). Leave nil for tools and tests.
    public init(restoreIdentifier: String? = nil) {
        (levels, levelOut) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
        (frames, frameOut) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(100))
        (status, statusOut) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.restoreIdentifier = restoreIdentifier
        super.init()
        for box in BoxPosition.allCases { snapshot.boxes[box] = BoxLinkStatus() }
    }

    /// Starts scanning (and asks for Bluetooth permission the first time). Safe to call again.
    public func start() {
        queue.async { [self] in
            running = true
            if central == nil {
                var options: [String: Any] = [CBCentralManagerOptionShowPowerAlertKey: true]
                #if os(iOS)
                if let restoreIdentifier { options[CBCentralManagerOptionRestoreIdentifierKey] = restoreIdentifier }
                #endif
                central = CBCentralManager(delegate: self, queue: queue, options: options)
            } else {
                scanIfNeeded()
            }
            startTicker()
        }
    }

    /// Stops audio, disconnects every box and stops scanning.
    public func stop() {
        queue.async { [self] in
            running = false
            if let box = wantedAudioBox { write(.stopAudio, to: box) }
            wantedAudioBox = nil
            central?.stopScan()
            for p in peripherals.values { central?.cancelPeripheralConnection(p) }
            ticker?.cancel(); ticker = nil
        }
    }

    /// Detection calls this when the loudest box changes: that box gets `control` = 1, the box
    /// that was streaming gets 0.
    public func streamAudio(from box: BoxPosition) {
        queue.async { [self] in
            guard wantedAudioBox != box else { return }
            if let old = wantedAudioBox { write(.stopAudio, to: old) }
            wantedAudioBox = box
            if audioReady.contains(box) { write(.startAudio, to: box) }
            publish()
        }
    }

    public func stopAudio() {
        queue.async { [self] in
            if let old = wantedAudioBox { write(.stopAudio, to: old) }
            wantedAudioBox = nil
            publish()
        }
    }

    // MARK: - queue-only helpers

    private func scanIfNeeded() {
        guard running, let central, central.state == .poweredOn else { return }
        // Reattach boxes iOS is already connected to (e.g. after an app relaunch).
        for p in central.retrievePeripherals(withIdentifiers: Array(boxByID.keys)) where p.state == .disconnected {
            central.connect(p)
        }
        if peripherals.count < BoxPosition.allCases.count, !central.isScanning {
            // Duplicates on: the name only comes in the scan response, which can arrive in a later
            // report than the advertisement with the service UUID. Scanning stops once all 4 are found.
            central.scanForPeripherals(withServices: [SoundBoxUUID.service],
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        } else if peripherals.count == BoxPosition.allCases.count, central.isScanning {
            central.stopScan()
        }
    }

    private func write(_ command: ControlCommand, to box: BoxPosition) {
        guard let p = peripherals[box], p.state == .connected, let c = control[box] else { return }
        p.writeValue(command.data, for: c, type: .withResponse)
        snapshot.boxes[box]?.streamingAudio = command == .startAudio
    }

    private func adopt(_ p: CBPeripheral, as box: BoxPosition) {
        peripherals[box] = p
        boxByID[p.identifier] = box
        p.delegate = self
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.publish() }
        t.resume()
        ticker = t
    }

    private func publish() { statusOut.yield(snapshot) }

    private func update(_ box: BoxPosition, _ change: (inout BoxLinkStatus) -> Void) {
        var s = snapshot.boxes[box] ?? BoxLinkStatus()
        change(&s)
        snapshot.boxes[box] = s
    }

    private func handleLevel(_ data: Data, from box: BoxPosition) {
        guard let pkt = try? LevelPacket(data) else { update(box) { $0.malformed += 1 }; return }
        let missed = lastLevelSeq[box].map { BLESequence.missed(previous: $0, current: pkt.seq) } ?? 0
        lastLevelSeq[box] = pkt.seq
        update(box) {
            $0.levelPackets += 1
            $0.levelMissed += missed
            $0.lastPeakDbfs = pkt.peakDbfs
            $0.lowBattery = pkt.lowBattery
        }
        levelOut.yield(pkt.boxLevel(box: box, receivedAt: Date()))
    }

    private func handleAudio(_ data: Data, from box: BoxPosition) {
        guard let pkt = try? AudioPacket(data), pkt.stepIndex <= 88 else {
            update(box) { $0.malformed += 1 }; return
        }
        let missed = lastAudioSeq[box].map { BLESequence.missed(previous: $0, current: pkt.seq) } ?? 0
        lastAudioSeq[box] = pkt.seq
        update(box) { $0.audioPackets += 1; $0.audioMissed += missed }
        frameOut.yield(SoundFrame(box: box, seq: pkt.seq, receivedAt: Date(), samples: IMAADPCM.decode(pkt)))
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEBoxSource: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        snapshot.bluetooth = switch central.state {
        case .poweredOn: .poweredOn
        case .poweredOff: .poweredOff
        case .unauthorized: .unauthorized
        case .unsupported: .unsupported
        case .resetting: .resetting
        default: .unknown
        }
        if central.state == .poweredOn {
            scanIfNeeded()
        } else {
            for box in BoxPosition.allCases where snapshot.boxes[box]?.state == .connected {
                update(box) { $0.state = .connecting; $0.streamingAudio = false }
            }
            audioReady.removeAll()
        }
        publish()
    }

    #if os(iOS)
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for p in restored {
            if let name = p.name, let box = BoxPosition(advertisedName: name) {
                adopt(p, as: box)
                update(box) { $0.state = p.state == .connected ? .connected : .connecting }
            }
        }
    }
    #endif

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // The name is in the scan response (box_config.h: it doesn't fit next to the 128-bit UUID).
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard boxByID[peripheral.identifier] == nil else { return }   // already ours
        guard let name, let box = BoxPosition(advertisedName: name) else {
            // No scan response (e.g. background scanning): connect and read the GAP name instead.
            if !unnamed.keys.contains(peripheral.identifier) {
                unnamed[peripheral.identifier] = peripheral
                peripheral.delegate = self
                central.connect(peripheral)
            }
            return
        }
        if let known = peripherals[box], known.identifier != peripheral.identifier, known.state != .disconnected {
            return   // a second box claiming the same position: keep the first
        }
        unnamed[peripheral.identifier] = nil
        adopt(peripheral, as: box)
        update(box) { $0.state = .connecting }
        central.connect(peripheral)
        scanIfNeeded()
        publish()
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if boxByID[peripheral.identifier] == nil, unnamed.removeValue(forKey: peripheral.identifier) != nil {
            // Connected without knowing which box this is: the GAP device name says.
            guard let name = peripheral.name, let box = BoxPosition(advertisedName: name),
                  peripherals[box].map({ $0.state == .disconnected }) ?? true else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            adopt(peripheral, as: box)
            scanIfNeeded()
        }
        guard let box = boxByID[peripheral.identifier] else { return }
        let fits = peripheral.maximumWriteValueLength(for: .withoutResponse) >= AudioPacket.byteCount
        update(box) { $0.state = .connected; $0.mtuOK = fits }
        lastLevelSeq[box] = nil
        lastAudioSeq[box] = nil
        peripheral.discoverServices([SoundBoxUUID.service])
        publish()
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        reconnect(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        reconnect(peripheral)
    }

    /// iOS keeps a pending connect alive with no timeout, so the box reconnects as soon as it is
    /// back in range, even with the app in the background.
    private func reconnect(_ peripheral: CBPeripheral) {
        unnamed[peripheral.identifier] = nil
        guard let box = boxByID[peripheral.identifier] else { return }
        audioReady.remove(box)
        control[box] = nil
        update(box) { $0.state = running ? .connecting : .notFound; $0.streamingAudio = false }
        if running { central?.connect(peripheral) }
        publish()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEBoxSource: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == SoundBoxUUID.service }) else { return }
        peripheral.discoverCharacteristics([SoundBoxUUID.level, SoundBoxUUID.audio, SoundBoxUUID.control], for: svc)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        guard let box = boxByID[peripheral.identifier] else { return }
        for c in service.characteristics ?? [] {
            switch c.uuid {
            case SoundBoxUUID.level, SoundBoxUUID.audio: peripheral.setNotifyValue(true, for: c)
            case SoundBoxUUID.control: control[box] = c
            default: break
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard let box = boxByID[peripheral.identifier], characteristic.uuid == SoundBoxUUID.audio,
              characteristic.isNotifying else { return }
        audioReady.insert(box)
        // Start audio only once the subscription is on, or the first packets are dropped by the box.
        write(wantedAudioBox == box ? .startAudio : .stopAudio, to: box)
        publish()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard let box = boxByID[peripheral.identifier], let data = characteristic.value else { return }
        switch characteristic.uuid {
        case SoundBoxUUID.level: handleLevel(data, from: box)
        case SoundBoxUUID.audio: handleAudio(data, from: box)
        default: break
        }
    }
}
