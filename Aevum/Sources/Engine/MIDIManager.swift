// MIDIManager.swift — CoreMIDI input routing to EngineBridge.
// Handles note on/off, CC→param mapping, virtual destination for DAW routing.

import Foundation
import CoreMIDI

enum XFParam: String, CaseIterable, Codable {
    case temperature
    case topK
    case cfgMusiccoca
    case cfgNotes
    case cfgDrums
    case unmaskWidth
    case seedRotation
    case volumeDb
    case drumless
    case onsetMode
    case midiGate
    case bypass
    case blend0
    case blend1
    case blend2
    case blend3
    case blend4
    case blend5
    case pca0
    case pca1
    case pca2
    case pca3
    case pca4
    case pca5
}

struct XFCCMap: Codable, Identifiable {
    var id = UUID()
    var cc: Int          // 0..127
    var param: XFParam
    var min: Float = 0.0 // source CC range (0..127)
    var max: Float = 127.0
    var targetMin: Float // mapped param range
    var targetMax: Float

    init(cc: Int, param: XFParam, targetMin: Float, targetMax: Float) {
        self.cc = cc
        self.param = param
        self.targetMin = targetMin
        self.targetMax = targetMax
    }
}

final class MIDIManager {
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var virtualIn: MIDIEndpointRef = 0
    private(set) var connectedSources: Set<MIDIEndpointRef> = []

    weak var bridge: EngineBridge?
    var ccMaps: [XFCCMap] = MIDIManager.defaultCCMaps()
    var onCC: ((Int, Int) -> Void)? // raw CC observer for MIDI-learn

    init(bridge: EngineBridge) {
        self.bridge = bridge
        let name = "Aevum" as CFString
        MIDIClientCreate(name, nil, nil, &client)
        let portName = "Aevum input" as CFString
        MIDIInputPortCreateWithBlock(client, portName, &inputPort) { [weak self] packetList, _ in
            self?.handle(packetList)
        }
        createVirtualDestination()
    }

    deinit {
        if virtualIn != 0 { MIDIEndpointDispose(virtualIn) }
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: - Virtual destination (lets DAWs/controllers route MIDI to Aevum)

    private func createVirtualDestination() {
        let name = "Aevum In" as CFString
        // MIDIReadBlock delivers a MIDIPacketList (MIDI 1.0 bytes), same
        // shape as the input-port callback.
        let callback: MIDIReadBlock = { [weak self] packetList, _ in
            self?.handle(packetList)
        }
        MIDIDestinationCreateWithBlock(client, name, &virtualIn, callback)
    }

    // MARK: - Source discovery / connection

    func connectAllSources() {
        let n = MIDIGetNumberOfSources()
        for i in 0..<n {
            let src = MIDIGetSource(i)
            connect(src)
        }
    }

    func connect(_ source: MIDIEndpointRef) {
        guard !connectedSources.contains(source) else { return }
        MIDIPortConnectSource(inputPort, source, nil)
        connectedSources.insert(source)
    }

    func disconnect(_ source: MIDIEndpointRef) {
        guard connectedSources.contains(source) else { return }
        MIDIPortDisconnectSource(inputPort, source)
        connectedSources.remove(source)
    }

    // MARK: - Packet parsing

    private func handle(_ packetList: UnsafePointer<MIDIPacketList>) {
        let n = packetList.pointee.numPackets
        // Get a pointer to the first packet embedded in the list; iterate
        // via MIDIPacketNext which advances by the packet's byte size.
        var packetPtr = withUnsafePointer(to: packetList.pointee.packet) {
            UnsafeMutablePointer<MIDIPacket>(mutating: $0)
        }
        for _ in 0..<n {
            let length = Int(packetPtr.pointee.length)
            withUnsafeBytes(of: packetPtr.pointee.data) { rawBuf in
                if let base = rawBuf.baseAddress {
                    parse(UnsafeRawPointer(base).assumingMemoryBound(to: UInt8.self),
                          count: length)
                }
            }
            packetPtr = MIDIPacketNext(packetPtr)
        }
    }

    private func parse(_ data: UnsafePointer<UInt8>, count: Int) {
        var i = 0
        while i < count {
            let status = data[i] & 0xF0
            let channel = data[i] & 0x0F
            switch status {
            case 0x90: // note on
                if i + 2 < count {
                    let note = Int32(data[i + 1])
                    let vel = data[i + 2]
                    if vel == 0 { bridge?.setNoteOff(note) }
                    else { bridge?.setNoteOn(note) }
                    i += 3
                } else { i = count }
            case 0x80: // note off
                if i + 2 < count {
                    let note = Int32(data[i + 1])
                    bridge?.setNoteOff(note)
                    i += 3
                } else { i = count }
            case 0xB0: // CC
                if i + 2 < count {
                    let cc = Int(data[i + 1])
                    let value = Int(data[i + 2])
                    onCC?(cc, value)
                    applyCC(cc, value)
                    i += 3
                } else { i = count }
            case 0xC0: // program change
                i += 2
            case 0xD0: // channel pressure
                i += 2
            case 0xE0: // pitch bend
                i += 3
            case 0xF0: // system messages — skip variable length
                if data[i] == 0xF0 {
                    while i < count && data[i] != 0xF7 { i += 1 }
                    i += 1
                } else {
                    i += 1
                }
            default:
                i += 1
            }
            _ = channel
        }
    }

    // MARK: - CC → param application

    private func applyCC(_ cc: Int, _ value: Int) {
        let fval = Float(value)
        for map in ccMaps where map.cc == cc {
            let norm = (fval - map.min) / (map.max - map.min)
            let mapped = map.targetMin + norm * (map.targetMax - map.targetMin)
            applyParam(map.param, value: mapped)
        }
    }

    func applyParam(_ param: XFParam, value: Float) {
        guard let bridge else { return }
        switch param {
        case .temperature:  bridge.setTemperature(value)
        case .topK:          bridge.setTopK(Int32(value))
        case .cfgMusiccoca:  bridge.setCfgMusiccoca(value)
        case .cfgNotes:      bridge.setCfgNotes(value)
        case .cfgDrums:      bridge.setCfgDrums(value)
        case .unmaskWidth:   bridge.setUnmaskWidth(Int32(value))
        case .seedRotation:  bridge.setSeedRotation(Int32(value))
        case .volumeDb:      bridge.setVolumeDb(value)
        case .drumless:      bridge.setDrumless(value > 0.5)
        case .onsetMode:     bridge.setOnsetMode(value > 0.5 ? .unmasked : .masked)
        case .midiGate:      bridge.setMidiGateEnabled(value > 0.5)
        case .bypass:        bridge.setBypass(value > 0.5)
        case .blend0:        bridge.setBlendWeightForIndex(0, weight: value)
        case .blend1:        bridge.setBlendWeightForIndex(1, weight: value)
        case .blend2:        bridge.setBlendWeightForIndex(2, weight: value)
        case .blend3:        bridge.setBlendWeightForIndex(3, weight: value)
        case .blend4:        bridge.setBlendWeightForIndex(4, weight: value)
        case .blend5:        bridge.setBlendWeightForIndex(5, weight: value)
        case .pca0:          bridge.setPcaCoeffForIndex(0, value: value)
        case .pca1:          bridge.setPcaCoeffForIndex(1, value: value)
        case .pca2:          bridge.setPcaCoeffForIndex(2, value: value)
        case .pca3:          bridge.setPcaCoeffForIndex(3, value: value)
        case .pca4:          bridge.setPcaCoeffForIndex(4, value: value)
        case .pca5:          bridge.setPcaCoeffForIndex(5, value: value)
        }
    }

    // MARK: - Default CC map

    static func defaultCCMaps() -> [XFCCMap] {
        [
            XFCCMap(cc: 1,  param: .cfgNotes,     targetMin: 0,  targetMax: 10),
            XFCCMap(cc: 2,  param: .cfgMusiccoca, targetMin: 0,  targetMax: 10),
            XFCCMap(cc: 3,  param: .cfgDrums,     targetMin: 0,  targetMax: 10),
            XFCCMap(cc: 4,  param: .temperature,  targetMin: 0.1, targetMax: 1.5),
            XFCCMap(cc: 5,  param: .topK,         targetMin: 1,   targetMax: 200),
            XFCCMap(cc: 64, param: .drumless,     targetMin: 0,   targetMax: 1), // sustain pedal
            XFCCMap(cc: 74, param: .blend0,       targetMin: 0,   targetMax: 1),
            XFCCMap(cc: 71, param: .blend1,       targetMin: 0,   targetMax: 1),
            XFCCMap(cc: 91, param: .blend2,       targetMin: 0,   targetMax: 1),
        ]
    }
}
