import Foundation
import simd

enum FurNoise {
    static func hash(_ ix: Int, _ iy: Int) -> Float {
        let x = UInt32(bitPattern: Int32(truncatingIfNeeded: ix))
        let y = UInt32(bitPattern: Int32(truncatingIfNeeded: iy))
        var n = x &* 374761393 &+ y &* 668265263
        n = (n ^ (n >> 13)) &* 1274126177
        return Float(n & 0x00FF_FFFF) / Float(0x00FF_FFFF)
    }

    static func value(_ p: SIMD2<Float>) -> Float {
        let x0 = Int(floor(p.x))
        let y0 = Int(floor(p.y))
        let fx = p.x - Float(x0)
        let fy = p.y - Float(y0)
        let sx = fx * fx * (3 - 2 * fx)
        let sy = fy * fy * (3 - 2 * fy)
        let a = hash(x0, y0)
        let b = hash(x0 + 1, y0)
        let c = hash(x0, y0 + 1)
        let d = hash(x0 + 1, y0 + 1)
        return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy
    }

    static func fbm(_ p: SIMD2<Float>, octaves: Int) -> Float {
        var v: Float = 0
        var a: Float = 0.5
        var f: Float = 1
        var shift = SIMD2<Float>(0, 0)
        let step = SIMD2<Float>(1.7, 9.2)
        for _ in 0..<octaves {
            v += a * value(p * f + shift)
            f *= 2.02
            a *= 0.5
            shift += step
        }
        return v
    }
}
