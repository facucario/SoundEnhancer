import XCTest
@testable import SoundEnhancer

final class DSPTests: XCTestCase {

    private func sine(_ frequency: Double, sampleRate: Double, length: Int, amplitude: Float) -> [Float] {
        (0..<length).map { i in
            amplitude * Float(sin(2.0 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    private func rms(_ samples: [Float], from start: Int) -> Float {
        var sum: Float = 0
        var count: Float = 0
        for i in start..<samples.count {
            sum += samples[i] * samples[i]
            count += 1
        }
        guard count > 0 else { return 0 }
        return sqrt(sum / count)
    }

    func testPassthroughAtZeroIntensity() {
        let dsp = SoundEnhancerDSP(sampleRate: 48000)
        dsp.setIntensity(0)

        let length = 1024
        var left = sine(1000, sampleRate: 48000, length: length, amplitude: 0.5)
        var right = sine(1000, sampleRate: 48000, length: length, amplitude: 0.5)
        let originalL = left
        let originalR = right

        dsp.process(left: &left, right: &right)

        for i in 0..<length {
            XCTAssertEqual(left[i], originalL[i], accuracy: 0.001)
            XCTAssertEqual(right[i], originalR[i], accuracy: 0.001)
        }
    }

    func testStereoWidthIncreasesAtFullIntensity() {
        let sampleRate: Double = 48000
        let dsp = SoundEnhancerDSP(sampleRate: sampleRate)
        let length = 48000

        let left = sine(1000, sampleRate: sampleRate, length: length, amplitude: 0.1)
        let right = left.map { -$0 }

        func diffRMS(_ l: [Float], _ r: [Float]) -> Float {
            var d = [Float](repeating: 0, count: l.count)
            for i in 0..<l.count { d[i] = l[i] - r[i] }
            return rms(d, from: length / 2)
        }

        var zeroL = left, zeroR = right
        dsp.setIntensity(0)
        dsp.reset()
        dsp.process(left: &zeroL, right: &zeroR)

        var fullL = left, fullR = right
        dsp.setIntensity(1)
        dsp.reset()
        dsp.process(left: &fullL, right: &fullR)

        XCTAssertGreaterThan(diffRMS(fullL, fullR), diffRMS(zeroL, zeroR) * 1.5)
    }

    func testLowShelfBoostsBassAtFullIntensity() {
        let sampleRate: Double = 48000
        let dsp = SoundEnhancerDSP(sampleRate: sampleRate)
        let length = 48000

        let bass = sine(80, sampleRate: sampleRate, length: length, amplitude: 0.1)

        var l0 = bass, r0 = bass
        dsp.setIntensity(0)
        dsp.reset()
        dsp.process(left: &l0, right: &r0)

        var l1 = bass, r1 = bass
        dsp.setIntensity(1)
        dsp.reset()
        dsp.process(left: &l1, right: &r1)

        let rms0 = rms(l0, from: length / 2)
        let rms1 = rms(l1, from: length / 2)

        XCTAssertGreaterThan(rms1, rms0 * 1.4)
    }

    func testNoClippingAtFullScale() {
        let sampleRate: Double = 48000
        let dsp = SoundEnhancerDSP(sampleRate: sampleRate)
        let length = 48000

        var left = sine(1000, sampleRate: sampleRate, length: length, amplitude: 0.99)
        var right = sine(1000, sampleRate: sampleRate, length: length, amplitude: 0.99)

        dsp.setIntensity(1)
        dsp.reset()
        dsp.process(left: &left, right: &right)

        for i in 0..<length {
            XCTAssertLessThanOrEqual(abs(left[i]), 1.0)
            XCTAssertLessThanOrEqual(abs(right[i]), 1.0)
        }
    }
}
