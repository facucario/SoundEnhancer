import CoreAudio
import Foundation

// Custom property selector shared with the HAL driver (FourCC 'SEcn').
// The menu-bar app configures the enhancer by writing this property to the
// virtual device object instead of opening a CoreAudio input stream, which is
// what previously triggered the macOS "microphone in use" indicator.
let kSoundEnhancerPropertyConfig: AudioObjectPropertySelector = 0x5345636E // 'SEcn'

// FourCC 'SErc'. Writing this to the virtual device forces the driver to tear
// down and re-bind its pass-through output IO proc. The app writes it after the
// system wakes from sleep, when coreaudiod has stopped the physical device's IO.
let kSoundEnhancerPropertyReconnect: AudioObjectPropertySelector = 0x53457263 // 'SErc'

// FourCC 'SEud'. The target physical output device's UID. AudioObjectIDs are
// assigned per HAL connection, so the numeric ID is not meaningful inside the
// driver's process; the UID is the stable key the driver re-resolves.
let kSoundEnhancerPropertyOutputUID: AudioObjectPropertySelector = 0x53457564 // 'SEud'

// Must match the C struct `SoundEnhancerConfig` in SoundEnhancerDriver.c:
// all 32-bit fields, no padding.
struct SEConfig: Equatable {
    var enabled: UInt32
    var xtcEnabled: UInt32
    var width: Float
    var bassDb: Float
    var trebleDb: Float
    var spatialMix: Float
    var xtcIntensity: Float
    var xtcSeparation: Float
    var xtcDistance: Float
    var masterGain: Float
    var outputDeviceID: UInt32
    var inputLevel: Float
    var outputLevel: Float

    init() {
        enabled = 1
        xtcEnabled = 0
        width = 2.0
        bassDb = 5.0
        trebleDb = 5.0
        spatialMix = 0.175
        xtcIntensity = 0.8
        xtcSeparation = 0.24
        xtcDistance = 0.50
        masterGain = 1.0
        outputDeviceID = 0
        inputLevel = 0
        outputLevel = 0
    }
}

enum DriverLink {

    private static func configAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kSoundEnhancerPropertyConfig,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    @discardableResult
    static func writeConfig(_ config: SEConfig, to deviceID: AudioDeviceID) -> Bool {
        var cfg = config
        var address = configAddress()
        let data: CFData = withUnsafeBytes(of: &cfg) { raw in
            CFDataCreate(nil, raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        var cfValue = Unmanaged.passUnretained(data)
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<Unmanaged<CFData>>.size), &cfValue)
        return status == noErr
    }

    static func readConfig(from deviceID: AudioDeviceID) -> SEConfig? {
        var address = configAddress()
        var cfValue: Unmanaged<CFData>?
        var size = UInt32(MemoryLayout<Unmanaged<CFData>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &size, &cfValue)
        guard status == noErr, let data = cfValue?.takeUnretainedValue() else { return nil }
        guard CFDataGetLength(data) == MemoryLayout<SEConfig>.size else { return nil }
        var cfg = SEConfig()
        CFDataGetBytes(data, CFRange(location: 0, length: CFDataGetLength(data)), &cfg)
        return cfg
    }

    @discardableResult
    static func reconnectOutput(to deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kSoundEnhancerPropertyReconnect,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 1
        let data: CFData = withUnsafeBytes(of: &value) { raw in
            CFDataCreate(nil, raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        var cfValue = Unmanaged.passUnretained(data)
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<Unmanaged<CFData>>.size), &cfValue)
        return status == noErr
    }

    @discardableResult
    static func writeOutputUID(_ uid: String, to deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kSoundEnhancerPropertyOutputUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let string = uid as CFString
        var cfValue = Unmanaged.passUnretained(string)
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<Unmanaged<CFString>>.size), &cfValue)
        return status == noErr
    }
}
