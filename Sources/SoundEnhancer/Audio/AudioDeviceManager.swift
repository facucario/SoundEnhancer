import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let inputChannels: Int
    let outputChannels: Int
    let nominalSampleRate: Double

    var displayName: String {
        name.isEmpty ? uid : name
    }
}

enum AudioDeviceManager {

    static func allDevices() -> [AudioDevice] {
        audioObjectIDs(selector: kAudioHardwarePropertyDevices).map { makeDevice(id: $0) }
    }

    static func outputDevices() -> [AudioDevice] {
        allDevices().filter { $0.outputChannels > 0 }
    }

    static func inputDevices() -> [AudioDevice] {
        allDevices().filter { $0.inputChannels > 0 }
    }

    static func defaultOutputDeviceID() -> AudioDeviceID {
        audioObjectID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    static func defaultInputDeviceID() -> AudioDeviceID {
        audioObjectID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    static func virtualDevice() -> AudioDevice? {
        allDevices().first {
            $0.uid.lowercased().contains("soundenhancer") || $0.name.lowercased().contains("soundenhancer")
        }
    }

    static func setDefaultOutputDevice(_ id: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = id
        _ = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
    }

    static func setVolume(_ id: AudioDeviceID, scalar: Float32) {
        for scope in [kAudioObjectPropertyScopeOutput, kAudioObjectPropertyScopeInput] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: scope,
                mElement: kAudioObjectPropertyElementMain)
            var value = scalar
            _ = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    static func setMuted(_ id: AudioDeviceID, _ muted: Bool) {
        for scope in [kAudioObjectPropertyScopeOutput, kAudioObjectPropertyScopeInput] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: scope,
                mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = muted ? 1 : 0
            _ = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }

    static func volumeDecibels(_ id: AudioDeviceID) -> Float {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeDecibels,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var value: Float32 = 0.0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0.0 }
        return value
    }

    static func setVolumeDecibels(_ id: AudioDeviceID, _ db: Float32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeDecibels,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var value = db
        _ = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    static func isMuted(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    static func device(id: AudioDeviceID) -> AudioDevice? {
        allDevices().first { $0.id == id }
    }

    static func addDeviceChangeListener(_ handler: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { _, _ in
            handler()
        }
    }

    static func addDefaultOutputChangeListener(_ handler: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { _, _ in
            handler()
        }
    }

    static func setBufferFrameSize(_ id: AudioDeviceID, frames: UInt32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = frames
        _ = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    static func nominalSampleRate(_ id: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    static func setNominalSampleRate(_ id: AudioDeviceID, rate: Double) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = rate
        _ = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
    }

    // MARK: - Property helpers

    private static func audioObjectIDs(selector: AudioObjectPropertySelector) -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBufferPointer { buf -> OSStatus in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, buf.baseAddress!)
        }
        guard status == noErr else { return [] }
        return ids
    }

    private static func audioObjectID(selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private static func makeDevice(id: AudioDeviceID) -> AudioDevice {
        AudioDevice(
            id: id,
            name: stringProperty(id, selector: kAudioObjectPropertyName),
            uid: stringProperty(id, selector: kAudioDevicePropertyDeviceUID),
            inputChannels: channelCount(id, scope: kAudioObjectPropertyScopeInput),
            outputChannels: channelCount(id, scope: kAudioObjectPropertyScopeOutput),
            nominalSampleRate: doubleProperty(id, selector: kAudioDevicePropertyNominalSampleRate))
    }

    private static func stringProperty(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfValue: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &cfValue) == noErr,
              let value = cfValue?.takeUnretainedValue() else { return "" }
        return value as String
    }

    private static func doubleProperty(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private static func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<UInt64>.alignment)
        defer { data.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, data) == noErr else { return 0 }
        let abl = data.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        var channels = 0
        for buffer in buffers {
            channels += Int(buffer.mNumberChannels)
        }
        return channels
    }
}
