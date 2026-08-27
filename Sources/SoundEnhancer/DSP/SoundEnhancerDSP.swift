import Foundation

final class SoundEnhancerDSP {
    static let minDelaySeconds = 0.003
    static let maxDelaySeconds = 0.012

    private(set) var sampleRate: Double
    private(set) var intensity: Float = 0

    private var lowShelfL = Biquad()
    private var lowShelfR = Biquad()
    private var highShelfL = Biquad()
    private var highShelfR = Biquad()
    private var midDipL = Biquad()
    private var midDipR = Biquad()
    private var haasLPF = Biquad()

    private var delayBuffer: [Float] = []
    private var delayLength: Int = 0
    private var delayWrite: Int = 0

    private var widthGain: Float = 1.0
    private var bassGainDb: Float = 0
    private var trebleGainDb: Float = 0
    private var haasMix: Float = 0
    private var haasDelaySamples: Float = 0

    private let haasLowPassFrequency: Double = 4000.0

    init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        allocateDelayLine()
        setParameters(width: 1.0, bassDb: 0, trebleDb: 0, spatialMix: 0)
    }

    func setSampleRate(_ sr: Double) {
        guard sr > 0, sr != sampleRate else { return }
        sampleRate = sr
        allocateDelayLine()
        recomputeFilters()
    }

    func setIntensity(_ value: Float) {
        let a = min(max(value, 0), 1)
        intensity = a
        setParameters(
            width: Float(1.0 + 2.0 * Double(a)),
            bassDb: Float(10.0 * Double(a)),
            trebleDb: Float(10.0 * Double(a)),
            spatialMix: Float(0.35 * Double(a)))
    }

    func setParameters(width: Float, bassDb: Float, trebleDb: Float, spatialMix: Float) {
        widthGain = min(max(width, 1.0), 3.0)
        bassGainDb = min(max(bassDb, 0), 10.0)
        trebleGainDb = min(max(trebleDb, 0), 10.0)
        haasMix = min(max(spatialMix, 0), 0.35)

        let normalized = haasMix / 0.35
        let delaySeconds = Self.minDelaySeconds + (Self.maxDelaySeconds - Self.minDelaySeconds) * Double(normalized)
        haasDelaySamples = Float(delaySeconds * sampleRate)

        recomputeFilters()
    }

    func reset() {
        lowShelfL.reset(); lowShelfR.reset()
        highShelfL.reset(); highShelfR.reset()
        midDipL.reset(); midDipR.reset()
        haasLPF.reset()
        for i in 0..<delayLength {
            delayBuffer[i] = 0
        }
        delayWrite = 0
    }

    private func allocateDelayLine() {
        let maxSamples = Int(ceil(Self.maxDelaySeconds * sampleRate)) + 4
        delayLength = maxSamples
        delayBuffer = [Float](repeating: 0, count: delayLength)
        delayWrite = 0
    }

    private func recomputeFilters() {
        let enhance = min(max((bassGainDb / 10.0 + trebleGainDb / 10.0 + haasMix / 0.35) / 3.0, 0), 1)
        let midGain = -2.0 * Double(enhance)

        lowShelfL = .lowShelf(sampleRate: sampleRate, frequency: 80, gainDb: Double(bassGainDb))
        lowShelfR = lowShelfL
        highShelfL = .highShelf(sampleRate: sampleRate, frequency: 9000, gainDb: Double(trebleGainDb))
        highShelfR = highShelfL
        midDipL = .peaking(sampleRate: sampleRate, frequency: 1000, gainDb: midGain, q: 0.9)
        midDipR = midDipL

        haasLPF = .lowPass(sampleRate: sampleRate, frequency: haasLowPassFrequency)
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
        for i in 0..<frameCount {
            let l = left[i]
            let r = right[i]

            let mid = 0.5 * (l + r)
            var side = 0.5 * (l - r) * widthGain

            var delayed: Float = 0
            if haasMix > 0 {
                let readPos = Float(delayWrite) - haasDelaySamples
                let base = Int(floor(readPos))
                let frac = readPos - Float(base)
                let i0 = ((base % delayLength) + delayLength) % delayLength
                let i1 = (i0 + 1) % delayLength
                delayed = delayBuffer[i0] * (1 - frac) + delayBuffer[i1] * frac
                delayed = haasLPF.process(delayed)
            }

            delayBuffer[delayWrite] = side
            delayWrite += 1
            if delayWrite >= delayLength { delayWrite = 0 }

            side += haasMix * delayed

            var outL = mid + side
            var outR = mid - side

            outL = lowShelfL.process(outL)
            outL = highShelfL.process(outL)
            outL = midDipL.process(outL)

            outR = lowShelfR.process(outR)
            outR = highShelfR.process(outR)
            outR = midDipR.process(outR)

            left[i] = softClip(outL)
            right[i] = softClip(outR)
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
