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

    var widthScale: Float { 0.82 + chub * 0.70 }
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

/// Top-down cat, head to the left, tail curling to the right.
/// Local units: the body is about one unit long. Keep in sync with CatScene.metal.
enum CatAnatomy {
    static let tailBase = SIMD2<Float>(0.36, 0.01)

    static func sample(_ p: SIMD2<Float>, pose: CatPose) -> CatSample {
        let ch = pose.widthScale
        let breath = 1 + pose.breath * 0.025
        let stretch = pose.delightKind == 1 ? 1 + pose.delight * 0.07 : 1
        let headShift: Float = pose.delightKind == 1 ? pose.delight * 0.035 : 0
        let knead: Float = pose.delightKind == 2 ? pose.delight : 0

        let body = sdEllipse(p, SIMD2(0.05, 0.02), SIMD2(0.48 * stretch, 0.195 * ch * breath))
        let belly = sdEllipse(p, SIMD2(0.06, 0.075), SIMD2(0.32 * stretch, 0.145 * ch))
        let chest = sdEllipse(p, SIMD2(-0.24 - headShift, 0.02), SIMD2(0.20, 0.155 * ch))
        let rump = sdEllipse(p, SIMD2(0.30, 0.015), SIMD2(0.20, 0.17 * ch))
        let neck = sdEllipse(p, SIMD2(-0.40 - headShift * 0.5, 0.02), SIMD2(0.12, 0.10 * ch))
        var torso = smin(body, belly, 0.12)
        torso = smin(torso, chest, 0.11)
        torso = smin(torso, rump, 0.11)
        torso = smin(torso, neck, 0.09)

        let head = sdEllipse(p, SIMD2(-0.56 - headShift, 0.015), SIMD2(0.182, 0.152))
        let earL = sdEllipse(p, SIMD2(-0.62 - headShift, -0.145 + pose.earL * 0.04), SIMD2(0.070, 0.085))
        let earR = sdEllipse(p, SIMD2(-0.50 - headShift, 0.150 + pose.earR * 0.04), SIMD2(0.065, 0.080))
        let earLI = sdEllipse(p, SIMD2(-0.62 - headShift, -0.12 + pose.earL * 0.03), SIMD2(0.016, 0.026))
        let earRI = sdEllipse(p, SIMD2(-0.50 - headShift, 0.125 + pose.earR * 0.03), SIMD2(0.014, 0.024))

        let chain = tailPoints(pose)
        let radii: [Float] = [0.055 * (0.9 + 0.1 * ch), 0.044 * ch, 0.030 * ch, 0.016 * ch]
        var tail = Float.greatestFiniteMagnitude
        for i in 0..<(chain.count - 1) {
            let seg = sdSegment(p, chain[i], chain[i + 1]) - (radii[i] * 0.65 + radii[i + 1] * 0.45)
            tail = min(tail, seg)
        }

        let pawSquash: Float = 1 - knead * 0.35
        let pawDrop: Float = knead * 0.02
        let pawA = sdEllipse(p, SIMD2(-0.30 - headShift, 0.145 + pawDrop), SIMD2(0.07, 0.038 * ch * pawSquash))
        let pawB = sdEllipse(p, SIMD2(-0.34 - headShift, -0.085 - pawDrop), SIMD2(0.055, 0.030 * pawSquash))

        var cat = smin(torso, head, 0.055)
        cat = smin(cat, tail, 0.04)
        cat = smin(cat, pawA, 0.03)
        cat = smin(cat, pawB, 0.03)
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
        consider(torso, .body)
        consider(head, .head)
        consider(min(earL, earR), .ear)
        consider(tail, .tail)
        consider(min(pawA, pawB), .paw)
        if min(earLI, earRI) < 0 { region = .innerEar }

        let zone: StrokeZone
        if cat > 0.03 {
            zone = .outside
        } else {
            switch region {
            case .head: zone = .head
            case .ear, .innerEar, .paw: zone = .other
            case .tail: zone = .tail
            case .body: zone = p.x < -0.18 ? .head : .back
            case .none: zone = .outside
            }
        }

        return CatSample(sdf: cat, region: region, grain: grain(p, region: region, chain: chain), zone: zone)
    }

    static func tailPoints(_ pose: CatPose) -> [SIMD2<Float>] {
        let s = pose.tailStretch
        let w = pose.tailSway
        return [
            SIMD2(0.36, 0.01),
            SIMD2(0.52, 0.13 + w),
            SIMD2(0.68 + s * 0.18, 0.10 + w * 0.6),
            SIMD2(0.84 + s * 0.42, -0.05 + w * 0.2),
        ]
    }

    static func grain(_ p: SIMD2<Float>, region: CatRegion, chain: [SIMD2<Float>]) -> SIMD2<Float> {
        var g = SIMD2<Float>(1, p.y * 0.28)
        if region == .tail, chain.count >= 2 {
            var best = Float.greatestFiniteMagnitude
            var tangent = SIMD2<Float>(1, 0)
            for i in 0..<(chain.count - 1) {
                let d = sdSegment(p, chain[i], chain[i + 1])
                if d < best {
                    best = d
                    tangent = chain[i + 1] - chain[i]
                }
            }
            g = tangent
        } else if region == .ear || region == .innerEar {
            g = p.y < 0 ? SIMD2(-0.2, -1) : SIMD2(-0.15, 1)
        }
        let len = simd_length(g)
        return len > 1e-4 ? g / len : SIMD2(1, 0)
    }

    static func sdEllipse(_ p: SIMD2<Float>, _ c: SIMD2<Float>, _ r: SIMD2<Float>) -> Float {
        let q = (p - c) / r
        return (simd_length(q) - 1) * min(r.x, r.y)
    }

    static func sdSegment(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let pa = p - a
        let ba = b - a
        let h = min(1, max(0, simd_dot(pa, ba) / max(1e-5, simd_dot(ba, ba))))
        return simd_length(pa - ba * h)
    }

    static func smin(_ a: Float, _ b: Float, _ k: Float) -> Float {
        let h = max(0, min(1, 0.5 + 0.5 * (b - a) / k))
        return b * (1 - h) + a * h - k * h * (1 - h)
    }
}
