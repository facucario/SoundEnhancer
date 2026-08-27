import Foundation

enum XTCGeometry: String, CaseIterable, Identifiable {
    case macBook
    case compactDesktop
    case studioMonitors
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .macBook: return "MacBook Speakers"
        case .compactDesktop: return "Desktop / Soundbar"
        case .studioMonitors: return "Studio Monitors"
        case .custom: return "Custom"
        }
    }

    var separation: Double {
        switch self {
        case .macBook: return 0.24
        case .compactDesktop: return 0.35
        case .studioMonitors: return 0.90
        case .custom: return 0.60
        }
    }

    var distance: Double {
        switch self {
        case .macBook: return 0.50
        case .compactDesktop: return 0.65
        case .studioMonitors: return 0.90
        case .custom: return 0.80
        }
    }
}

final class CrosstalkCancellationDSP {

    static let speedOfSound: Double = 343.0
    static let earSeparation: Double = 0.175
    static let minDelaySamples: Float = 4
    static let maxDelaySamples = 2048

    private struct FilterChain {
        var bass = Biquad()
        var shadow = Biquad()
        var treble = Biquad()

        mutating func configure(sampleRate: Double) {
            bass = .highPass(sampleRate: sampleRate, frequency: 200)
            shadow = .lowShelf(sampleRate: sampleRate, frequency: 2500, gainDb: -6)
            treble = .highShelf(sampleRate: sampleRate, frequency: 10000, gainDb: -18)
        }

        mutating func reset() {
            bass.reset()
            shadow.reset()
            treble.reset()
        }

        @inline(__always)
        mutating func process(_ x: Float) -> Float {
            var y = bass.process(x)
            y = shadow.process(y)
            y = treble.process(y)
            return y
        }
    }

    private(set) var sampleRate: Double
    private(set) var intensity: Float = 0
    private(set) var enabled = false
    private(set) var speakerSeparation: Double = 0.24
    private(set) var listenerDistance: Double = 0.50

    private(set) var delaySamples: Float = 0
    private(set) var gain: Float = 0

    private var leftChain = FilterChain()
    private var rightChain = FilterChain()

    private var leftDelay: [Float] = []
    private var rightDelay: [Float] = []
    private var delayLength = 0
    private var writeIndex = 0

    init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        allocateDelayLine()
        configureFilters()
        recomputeGeometry()
    }

    func setSampleRate(_ sr: Double) {
        guard sr > 0, sr != sampleRate else { return }
        sampleRate = sr
        allocateDelayLine()
        configureFilters()
        recomputeGeometry()
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        reset()
    }

    func setIntensity(_ value: Float) {
        intensity = min(max(value, 0), 1)
        recomputeGeometry()
    }

    func setGeometry(separation: Double, distance: Double) {
        speakerSeparation = min(max(separation, 0.05), 5.0)
        listenerDistance = min(max(distance, 0.05), 5.0)
        recomputeGeometry()
    }

    func reset() {
        leftChain.reset()
        rightChain.reset()
        for i in 0..<delayLength {
            leftDelay[i] = 0
            rightDelay[i] = 0
        }
        writeIndex = 0
    }

    private func allocateDelayLine() {
        delayLength = Self.maxDelaySamples + 8
        leftDelay = [Float](repeating: 0, count: delayLength)
        rightDelay = [Float](repeating: 0, count: delayLength)
        writeIndex = 0
    }

    private func configureFilters() {
        leftChain.configure(sampleRate: sampleRate)
        rightChain.configure(sampleRate: sampleRate)
    }

    private func recomputeGeometry() {
        let s = speakerSeparation
        let d = listenerDistance
        let a = Self.earSeparation

        let ri = sqrt(d * d + pow((s - a) * 0.5, 2))
        let rc = sqrt(d * d + pow((s + a) * 0.5, 2))

        let deltaT = (rc - ri) / Self.speedOfSound
        var dn = Float(deltaT * sampleRate)
        dn = max(dn, Self.minDelaySamples)
        dn = min(dn, Float(Self.maxDelaySamples))
        delaySamples = dn

        gain = Float(ri / rc) * intensity
    }

    @inline(__always)
    private func readDelay(_ buffer: [Float], delay: Float) -> Float {
        let pos = Float(writeIndex) - delay
        let ipRaw = Int(floor(pos))
        let frac = pos - Float(ipRaw)
        let ip = ((ipRaw % delayLength) + delayLength) % delayLength

        let i0 = (ip - 1 + delayLength) % delayLength
        let i1 = ip
        let i2 = (ip + 1) % delayLength
        let i3 = (ip + 2) % delayLength

        let x0 = buffer[i0]
        let x1 = buffer[i1]
        let x2 = buffer[i2]
        let x3 = buffer[i3]

        let c3 = 0.5 * (-x0 + 3 * x1 - 3 * x2 + x3)
        let c2 = 0.5 * (2 * x0 - 5 * x1 + 4 * x2 - x3)
        let c1 = 0.5 * (x2 - x0)
        return ((c3 * frac + c2) * frac + c1) * frac + x1
    }

    @inline(__always)
    private func softClip(_ x: Float) -> Float {
        let threshold: Float = 0.891
        let ax = abs(x)
        if ax <= threshold {
            return x
        }
        let sign: Float = x < 0 ? -1 : 1
        let over = (ax - threshold) / (1.0 - threshold)
        var y = sign * (threshold + (1.0 - threshold) * tanhf(over))
        if y > 1.0 { y = 1.0 }
        if y < -1.0 { y = -1.0 }
        return y
    }

    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard frameCount > 0 else { return }

        if !enabled || intensity <= 0 {
            for i in 0..<frameCount {
                leftDelay[writeIndex] = left[i]
                rightDelay[writeIndex] = right[i]
                writeIndex += 1
                if writeIndex >= delayLength { writeIndex = 0 }
            }
            return
        }

        for i in 0..<frameCount {
            let l = left[i]
            let r = right[i]

            let rPast = readDelay(rightDelay, delay: delaySamples)
            let lPast = readDelay(leftDelay, delay: delaySamples)

            let lCancel = gain * leftChain.process(rPast)
            let rCancel = gain * rightChain.process(lPast)

            var outL = l - lCancel
            var outR = r - rCancel

            outL = softClip(outL)
            outR = softClip(outR)

            leftDelay[writeIndex] = outL
            rightDelay[writeIndex] = outR
            writeIndex += 1
            if writeIndex >= delayLength { writeIndex = 0 }

            left[i] = outL
            right[i] = outR
        }
    }

    func process(left: inout [Float], right: inout [Float]) {
        guard left.count == right.count, !left.isEmpty else { return }
        let count = left.count
        left.withUnsafeMutableBufferPointer { lb in
            right.withUnsafeMutableBufferPointer { rb in
                process(left: lb.baseAddress!, right: rb.baseAddress!, frameCount: count)
            }
        }
    }
}
