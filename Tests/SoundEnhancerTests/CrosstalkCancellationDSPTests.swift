import XCTest
@testable import SoundEnhancer

final class CrosstalkCancellationDSPTests: XCTestCase {

    private func sine(_ frequency: Double, sampleRate: Double, length: Int, amplitude: Float) -> [Float] {
        (0..<length).map { i in
            amplitude * Float(sin(2.0 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    func testPassthroughWhenDisabled() {
        let dsp = CrosstalkCancellationDSP(sampleRate: 48000)
        dsp.setEnabled(false)
        dsp.setIntensity(1)
        dsp.setGeometry(separation: 0.24, distance: 0.50)

        let length = 1024
        var left = sine(1000, sampleRate: 48000, length: length, amplitude: 0.5)
        var right = sine(1000, sampleRate: 48000, length: length, amplitude: 0.5).map { -$0 }
        let originalL = left
        let originalR = right

        dsp.process(left: &left, right: &right)

        for i in 0..<length {
            XCTAssertEqual(left[i], originalL[i], accuracy: 0.0001)
            XCTAssertEqual(right[i], originalR[i], accuracy: 0.0001)
        }
    }

    func testPassthroughAtZeroIntensity() {
        let dsp = CrosstalkCancellationDSP(sampleRate: 48000)
        dsp.setEnabled(true)
        dsp.setIntensity(0)
        dsp.setGeometry(separation: 0.35, distance: 0.65)

        let length = 1024
        var left = sine(500, sampleRate: 48000, length: length, amplitude: 0.5)
        var right = sine(500, sampleRate: 48000, length: length, amplitude: 0.5).map { -$0 }
        let originalL = left
        let originalR = right

        dsp.process(left: &left, right: &right)

        for i in 0..<length {
            XCTAssertEqual(left[i], originalL[i], accuracy: 0.0001)
            XCTAssertEqual(right[i], originalR[i], accuracy: 0.0001)
        }
    }

    func testMacBookGeometryDelayAndGain() {
        let dsp = CrosstalkCancellationDSP(sampleRate: 48000)
        dsp.setGeometry(separation: 0.24, distance: 0.50)
        dsp.setIntensity(1)

        let a = CrosstalkCancellationDSP.earSeparation
        let c = CrosstalkCancellationDSP.speedOfSound
        let ri = sqrt(0.50 * 0.50 + pow((0.24 - a) * 0.5, 2))
        let rc = sqrt(0.50 * 0.50 + pow((0.24 + a) * 0.5, 2))

        let expectedDelay = Float((rc - ri) / c * 48000)
        XCTAssertEqual(dsp.delaySamples, expectedDelay, accuracy: 0.1)
        XCTAssertEqual(dsp.gain, Float(ri / rc), accuracy: 0.0001)
    }

    func testStudioMonitorsLongerDelayThanMacBook() {
        let mac = CrosstalkCancellationDSP(sampleRate: 48000)
        mac.setGeometry(separation: 0.24, distance: 0.50)
        let studio = CrosstalkCancellationDSP(sampleRate: 48000)
        studio.setGeometry(separation: 0.90, distance: 0.90)

        XCTAssertGreaterThan(studio.delaySamples, mac.delaySamples)
    }

    func testMonoInputStaysSymmetric() {
        let dsp = CrosstalkCancellationDSP(sampleRate: 48000)
        dsp.setEnabled(true)
        dsp.setIntensity(0.8)
        dsp.setGeometry(separation: 0.24, distance: 0.50)

        let length = 48000
        let mono = sine(1000, sampleRate: 48000, length: length, amplitude: 0.3)
        var left = mono
        var right = mono

        dsp.process(left: &left, right: &right)

        for i in 0..<length {
            XCTAssertEqual(left[i], right[i], accuracy: 0.0005)
        }
    }

    func testSideInputStaysAntiSymmetric() {
        let dsp = CrosstalkCancellationDSP(sampleRate: 48000)
        dsp.setEnabled(true)
        dsp.setIntensity(0.8)
        dsp.setGeometry(separation: 0.24, distance: 0.50)

        let length = 48000
        let side = sine(1000, sampleRate: 48000, length: length, amplitude: 0.3)
        var left = side
        var right = side.map { -$0 }

        dsp.process(left: &left, right: &right)

        for i in 0..<length {
            XCTAssertEqual(left[i], -right[i], accuracy: 0.0005)
        }
    }

    func testCancellationChangesOutput() {
        let dsp = CrosstalkCancellationDSP(sampleRate: 48000)
        dsp.setEnabled(true)
        dsp.setIntensity(1)
        dsp.setGeometry(separation: 0.24, distance: 0.50)

        let length = 48000
        let leftIn = sine(1000, sampleRate: 48000, length: length, amplitude: 0.2)
        let rightIn = [Float](repeating: 0, count: length)

        var left = leftIn, right = rightIn
        dsp.process(left: &left, right: &right)

        var changed = false
        for i in 0..<length {
            if abs(left[i] - leftIn[i]) > 0.001 || abs(right[i] - rightIn[i]) > 0.001 {
                changed = true
                break
            }
        }
        XCTAssertTrue(changed, "XTC should modify the output when enabled")
    }

    func testNoNaNOrOverflow() {
        let dsp = CrosstalkCancellationDSP(sampleRate: 48000)
        dsp.setEnabled(true)
        dsp.setIntensity(1)
        dsp.setGeometry(separation: 0.90, distance: 0.90)

        let length = 48000
        var left = sine(1000, sampleRate: 48000, length: length, amplitude: 0.99)
        var right = sine(1234, sampleRate: 48000, length: length, amplitude: 0.99)

        dsp.process(left: &left, right: &right)

        for i in 0..<length {
            XCTAssertTrue(left[i].isFinite)
            XCTAssertTrue(right[i].isFinite)
            XCTAssertLessThanOrEqual(abs(left[i]), 1.0)
            XCTAssertLessThanOrEqual(abs(right[i]), 1.0)
        }
    }
}
