import Foundation

struct Biquad {
    private(set) var b0: Float = 1
    private(set) var b1: Float = 0
    private(set) var b2: Float = 0
    private(set) var a1: Float = 0
    private(set) var a2: Float = 0

    private var x1: Float = 0
    private var x2: Float = 0
    private var y1: Float = 0
    private var y2: Float = 0

    init() {}

    mutating func reset() {
        x1 = 0; x2 = 0; y1 = 0; y2 = 0
    }

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }

    static func lowShelf(sampleRate: Double, frequency: Double, gainDb: Double, q: Double = 0.707) -> Biquad {
        let A = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let sqrtA = sqrt(A)
        let a0 = (A + 1) + (A - 1) * cosw + 2 * sqrtA * alpha

        var b = Biquad()
        b.b0 = Float(A * ((A + 1) - (A - 1) * cosw + 2 * sqrtA * alpha) / a0)
        b.b1 = Float(2 * A * ((A - 1) - (A + 1) * cosw) / a0)
        b.b2 = Float(A * ((A + 1) - (A - 1) * cosw - 2 * sqrtA * alpha) / a0)
        b.a1 = Float(-2 * ((A - 1) + (A + 1) * cosw) / a0)
        b.a2 = Float(((A + 1) + (A - 1) * cosw - 2 * sqrtA * alpha) / a0)
        return b
    }

    static func highShelf(sampleRate: Double, frequency: Double, gainDb: Double, q: Double = 0.707) -> Biquad {
        let A = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let sqrtA = sqrt(A)
        let a0 = (A + 1) - (A - 1) * cosw + 2 * sqrtA * alpha

        var b = Biquad()
        b.b0 = Float(A * ((A + 1) + (A - 1) * cosw + 2 * sqrtA * alpha) / a0)
        b.b1 = Float(-2 * A * ((A - 1) + (A + 1) * cosw) / a0)
        b.b2 = Float(A * ((A + 1) + (A - 1) * cosw - 2 * sqrtA * alpha) / a0)
        b.a1 = Float(2 * ((A - 1) - (A + 1) * cosw) / a0)
        b.a2 = Float(((A + 1) - (A - 1) * cosw - 2 * sqrtA * alpha) / a0)
        return b
    }

    static func peaking(sampleRate: Double, frequency: Double, gainDb: Double, q: Double = 0.707) -> Biquad {
        let A = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let a0 = 1 + alpha / A

        var b = Biquad()
        b.b0 = Float((1 + alpha * A) / a0)
        b.b1 = Float((-2 * cosw) / a0)
        b.b2 = Float((1 - alpha * A) / a0)
        b.a1 = Float((-2 * cosw) / a0)
        b.a2 = Float((1 - alpha / A) / a0)
        return b
    }

    static func highPass(sampleRate: Double, frequency: Double, q: Double = 0.707) -> Biquad {
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let a0 = 1 + alpha
        let k = (1 + cosw) / 2

        var b = Biquad()
        b.b0 = Float(k / a0)
        b.b1 = Float(-2 * k / a0)
        b.b2 = Float(k / a0)
        b.a1 = Float(-2 * cosw / a0)
        b.a2 = Float((1 - alpha) / a0)
        return b
    }

    static func lowPass(sampleRate: Double, frequency: Double, q: Double = 0.707) -> Biquad {
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let a0 = 1 + alpha
        let k = (1 - cosw) / 2

        var b = Biquad()
        b.b0 = Float(k / a0)
        b.b1 = Float(2 * k / a0)
        b.b2 = Float(k / a0)
        b.a1 = Float(-2 * cosw / a0)
        b.a2 = Float((1 - alpha) / a0)
        return b
    }
}
