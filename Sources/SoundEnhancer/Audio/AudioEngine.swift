import AudioToolbox
import CoreAudio
import Foundation

enum AudioEngineError: Error, LocalizedError {
    case componentNotFound
    case noDevice(String)
    case coreAudio(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .componentNotFound:
            return "CoreAudio component not found"
        case .noDevice(let message):
            return message
        case .coreAudio(let message, let status):
            return "\(message) (error \(status))"
        }
    }
}

final class AudioEngine {

    static let maxFramesPerSlice: Int = 4096

    let dsp = SoundEnhancerDSP()

    private(set) var inputDeviceID: AudioDeviceID?
    private(set) var outputDeviceID: AudioDeviceID?
    private(set) var sampleRate: Double = 48000
    private(set) var bufferSize: UInt32 = 256
    private(set) var isRunning = false
    private(set) var inputLevel: Float = 0
    private(set) var outputLevel: Float = 0

    private var inputUnit: AudioUnit?
    private var outputUnit: AudioUnit?

    private let ringBuffer = RingBuffer(capacity: 1 << 15)

    private let inputLeft: UnsafeMutablePointer<Float>
    private let inputRight: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>
    private let inputABLPtr: UnsafeMutablePointer<AudioBufferList>

    init() {
        inputLeft = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxFramesPerSlice)
        inputRight = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxFramesPerSlice)
        scratch = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxFramesPerSlice * 2)

        let bufferCount = 2
        let offset = MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers) ?? 0
        let totalSize = offset + bufferCount * MemoryLayout<AudioBuffer>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: totalSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        inputABLPtr = raw.assumingMemoryBound(to: AudioBufferList.self)

        let buffers = UnsafeMutableAudioBufferListPointer(inputABLPtr)
        buffers.unsafeMutablePointer.pointee.mNumberBuffers = 2
        buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(Self.maxFramesPerSlice * MemoryLayout<Float>.size), mData: UnsafeMutableRawPointer(inputLeft))
        buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(Self.maxFramesPerSlice * MemoryLayout<Float>.size), mData: UnsafeMutableRawPointer(inputRight))
    }

    deinit {
        stop()
        inputLeft.deallocate()
        inputRight.deallocate()
        scratch.deallocate()
        UnsafeMutableRawPointer(inputABLPtr).deallocate()
    }

    func start(inputDeviceID: AudioDeviceID, outputDeviceID: AudioDeviceID, bufferSize: UInt32) throws {
        stop()
        self.inputDeviceID = inputDeviceID
        self.outputDeviceID = outputDeviceID
        self.bufferSize = bufferSize
        try configureAndStart()
    }

    func stop() {
        if let u = outputUnit {
            AudioOutputUnitStop(u)
            AudioComponentInstanceDispose(u)
        }
        if let u = inputUnit {
            AudioOutputUnitStop(u)
            AudioComponentInstanceDispose(u)
        }
        inputUnit = nil
        outputUnit = nil
        isRunning = false
        dsp.reset()
    }

    func setIntensity(_ value: Float) {
        dsp.setIntensity(value)
    }

    func setParameters(width: Float, bassDb: Float, trebleDb: Float, spatialMix: Float) {
        dsp.setParameters(width: width, bassDb: bassDb, trebleDb: trebleDb, spatialMix: spatialMix)
    }

    // MARK: - Configuration

    private func configureAndStart() throws {
        guard let inID = inputDeviceID else { throw AudioEngineError.noDevice("No input device selected") }
        guard let outID = outputDeviceID, outID != 0 else { throw AudioEngineError.noDevice("No output device selected") }

        sampleRate = AudioDeviceManager.device(id: outID)?.nominalSampleRate ?? 48000
        if sampleRate <= 0 { sampleRate = 48000 }
        dsp.setSampleRate(sampleRate)

        AudioDeviceManager.setBufferFrameSize(inID, frames: bufferSize)
        AudioDeviceManager.setBufferFrameSize(outID, frames: bufferSize)

        let inUnit = try createInputUnit(deviceID: inID)
        let outUnit = try createOutputUnit(deviceID: outID)

        inputUnit = inUnit
        outputUnit = outUnit

        do {
            try check(AudioOutputUnitStart(outUnit), "start output unit")
            try check(AudioOutputUnitStart(inUnit), "start input unit")
        } catch {
            stop()
            throw error
        }
        isRunning = true
    }

    private func createInputUnit(deviceID: AudioDeviceID) throws -> AudioUnit {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw AudioEngineError.componentNotFound
        }
        var unit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &unit), "create input unit")
        guard let au = unit else { throw AudioEngineError.componentNotFound }

        do {
            var enable: UInt32 = 1
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, UInt32(MemoryLayout<UInt32>.size)), "enable input IO")
            var disable: UInt32 = 0
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disable, UInt32(MemoryLayout<UInt32>.size)), "disable input output IO")

            var device = deviceID
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size)), "set input device")

            var asbd = makeClientASBD(sampleRate: sampleRate)
            try check(AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &asbd, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "set input client format")

            var callback = AURenderCallbackStruct(inputProc: inputRenderCallback, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "set input callback")

            var maxFrames = UInt32(Self.maxFramesPerSlice)
            try check(AudioUnitSetProperty(au, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, UInt32(MemoryLayout<UInt32>.size)), "set input max frames")

            try check(AudioUnitInitialize(au), "initialize input unit")
        } catch {
            AudioComponentInstanceDispose(au)
            throw error
        }
        return au
    }

    private func createOutputUnit(deviceID: AudioDeviceID) throws -> AudioUnit {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw AudioEngineError.componentNotFound
        }
        var unit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &unit), "create output unit")
        guard let au = unit else { throw AudioEngineError.componentNotFound }

        do {
            var enable: UInt32 = 1
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enable, UInt32(MemoryLayout<UInt32>.size)), "enable output IO")
            var disable: UInt32 = 0
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &disable, UInt32(MemoryLayout<UInt32>.size)), "disable output input IO")

            var device = deviceID
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size)), "set output device")

            var asbd = makeClientASBD(sampleRate: sampleRate)
            try check(AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &asbd, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "set output client format")

            var callback = AURenderCallbackStruct(inputProc: outputRenderCallback, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
            try check(AudioUnitSetProperty(au, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "set output render callback")

            try check(AudioUnitInitialize(au), "initialize output unit")
        } catch {
            AudioComponentInstanceDispose(au)
            throw error
        }
        return au
    }

    private func makeClientASBD(sampleRate: Double, channels: UInt32 = 2) -> AudioStreamBasicDescription {
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = sampleRate
        asbd.mFormatID = kAudioFormatLinearPCM
        asbd.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved
        asbd.mBitsPerChannel = 32
        asbd.mChannelsPerFrame = channels
        asbd.mBytesPerFrame = 4
        asbd.mFramesPerPacket = 1
        asbd.mBytesPerPacket = 4
        return asbd
    }

    private func check(_ status: OSStatus, _ context: String) throws {
        guard status == noErr else {
            throw AudioEngineError.coreAudio(context, status)
        }
    }

    // MARK: - Render callbacks

    fileprivate func renderInput(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        bus: UInt32,
        frames: UInt32
    ) -> OSStatus {
        guard let unit = inputUnit else { return noErr }
        let n = Int(frames)
        if n > Self.maxFramesPerSlice { return noErr }

        let status = AudioUnitRender(unit, flags, timestamp, bus, frames, inputABLPtr)
        guard status == noErr else { return status }

        var peak: Float = 0
        for i in 0..<n {
            let a = abs(inputLeft[i]); if a > peak { peak = a }
            let b = abs(inputRight[i]); if b > peak { peak = b }
        }
        inputLevel = peak

        dsp.process(left: inputLeft, right: inputRight, frameCount: n)

        for i in 0..<n {
            scratch[i * 2] = inputLeft[i]
            scratch[i * 2 + 1] = inputRight[i]
        }
        ringBuffer.write(scratch, count: n * 2)
        return noErr
    }

    fileprivate func renderOutput(frames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let ioData else { return noErr }
        let n = Int(frames)
        let samples = n * 2
        let read = ringBuffer.read(scratch, count: samples)
        if read < samples {
            for i in read..<samples {
                scratch[i] = 0
            }
        }
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        guard buffers.count >= 2 else { return noErr }
        let left = buffers[0].mData?.assumingMemoryBound(to: Float.self)
        let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
        guard let l = left, let r = right else { return noErr }
        var peak: Float = 0
        for i in 0..<n {
            l[i] = scratch[i * 2]
            r[i] = scratch[i * 2 + 1]
            let a = abs(l[i]); if a > peak { peak = a }
        }
        outputLevel = peak
        return noErr
    }
}

private func inputRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let engine = Unmanaged<AudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    return engine.renderInput(flags: ioActionFlags, timestamp: inTimeStamp, bus: inBusNumber, frames: inNumberFrames)
}

private func outputRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let engine = Unmanaged<AudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    return engine.renderOutput(frames: inNumberFrames, ioData: ioData)
}
