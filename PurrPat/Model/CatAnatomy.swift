import Foundation
import simd

struct CatPose: Equatable {
    var chub: Float = 0.35
    var breath: Float = 0
    var earL: Float = 0
    var earR: Float = 0
    var tailStretch: Float = 0
    var tailSway: Float = 0
    var delight: Float = 0
    var delightKind: Int = 0

    var widthScale: Float { 0.96 + chub * 0.08 }
}

enum CatRegion: Int {
    case none, body, head, ear, innerEar, tail, paw
}

struct CatSample {
    var sdf: Float
    var region: CatRegion
    var grain: SIMD2<Float>
    var zone: StrokeZone
}

/// Top-down cat in plate UV (origin top-left, y down). The same pose is in every coat.
/// Keep the centres in sync with CatScene.metal.
enum CatAnatomy {
    static let tailBase = SIMD2<Float>(0.48, 0.64)
    static let torsoCenter = SIMD2<Float>(0.48, 0.47)

    static func sample(_ p: SIMD2<Float>, pose: CatPose) -> CatSample {
        let ch = pose.widthScale
        let breath = 1 + pose.breath * 0.02
        let head = sdEllipse(p, SIMD2(0.48, 0.268), SIMD2(0.125 * ch, 0.072))
        let earL = sdEllipse(p, SIMD2(0.385, 0.218 + pose.earL * 0.008), SIMD2(0.055, 0.042))
        let earR = sdEllipse(p, SIMD2(0.575, 0.216 + pose.earR * 0.008), SIMD2(0.055, 0.042))
        let body = sdEllipse(p, SIMD2(0.48, 0.47), SIMD2(0.185 * ch * breath, 0.165 * breath))

        let chain = tailPoints(pose)
        let radii: [Float] = [0.042, 0.034, 0.026, 0.018]
        var tail = Float.greatestFiniteMagnitude
        if chain.count >= 2 {
            for i in 0..<(chain.count - 1) {
                let seg = sdSegment(p, chain[i], chain[i + 1]) - (radii[i] * 0.55 + radii[i + 1] * 0.45)
                tail = min(tail, seg)
            }
        }

        var cat = min(head, body)
        cat = min(cat, tail)
        cat = min(cat, earL)
        cat = min(cat, earR)

        var region: CatRegion = .none
        var best = Float.greatestFiniteMagnitude
        func consider(_ sdf: Float, _ kind: CatRegion) {
            if sdf < best {
                best = sdf
                region = kind
            }
        }
        consider(body, .body)
        consider(head, .head)
        consider(min(earL, earR), .ear)
        consider(tail, .tail)

        let zone: StrokeZone
        if cat > 0.02 {
            zone = .outside
        } else {
            switch region {
            case .head: zone = .head
            case .body: zone = p.y < 0.36 ? .head : .back
            case .tail: zone = .tail
            case .ear, .innerEar, .paw, .none: zone = cat < 0.02 ? .other : .outside
            }
        }
        return CatSample(sdf: cat, region: region, grain: grain(p, region: region, chain: chain), zone: zone)
    }

    static func tailPoints(_ pose: CatPose) -> [SIMD2<Float>] {
        let s = pose.tailStretch
        let w = pose.tailSway
        return [
            SIMD2(0.48, 0.63),
            SIMD2(0.40 - w * 0.25, 0.72),
            SIMD2(0.31 - w * 0.40, 0.775),
            SIMD2(0.255 - w * 0.20 - s * 0.03, 0.71 - s * 0.025),
        ]
    }

    static func grain(_ p: SIMD2<Float>, region: CatRegion, chain: [SIMD2<Float>]) -> SIMD2<Float> {
        var g = SIMD2<Float>(0, 1)
        if region == .tail, chain.count >= 2 {
            var best = Float.greatestFiniteMagnitude
            var tangent = SIMD2<Float>(0, 1)
            for i in 0..<(chain.count - 1) {
                let d = sdSegment(p, chain[i], chain[i + 1])
                if d < best {
                    best = d
                    tangent = chain[i + 1] - chain[i]
                }
            }
            g = tangent
        } else if region == .ear || region == .innerEar {
            g = p.x < 0.48 ? SIMD2(-0.25, -0.9) : SIMD2(0.25, -0.9)
        }
        let len = simd_length(g)
        return len > 1e-4 ? g / len : SIMD2(0, 1)
    }

    static func sdEllipse(_ p: SIMD2<Float>, _ c: SIMD2<Float>, _ r: SIMD2<Float>) -> Float {
        let q = (p - c) / simd_max(r, SIMD2(repeating: 1e-3))
        return (simd_length(q) - 1) * min(r.x, r.y)
    }

    static func sdSegment(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let pa = p - a
        let ba = b - a
        let h = min(1, max(0, simd_dot(pa, ba) / max(1e-5, simd_dot(ba, ba))))
        return simd_length(pa - ba * h)
    }
}
