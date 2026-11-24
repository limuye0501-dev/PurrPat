import Foundation
import simd

enum CoatColor {
    static func albedo(_ coat: Coat, p: SIMD2<Float>, region: CatRegion, along: Float) -> SIMD3<Float> {
        let n = FurNoise.fbm(p * 2.2 + 3, octaves: 3)
        let n2 = FurNoise.fbm(p * 2.6 + 30, octaves: 3)
        var color: SIMD3<Float>
        switch coat {
        case .midnight:
            color = SIMD3(0.055, 0.050, 0.060) * (0.88 + 0.22 * n)
        case .ember:
            let stripe = band(p.x * 15 + n * 4)
            let base = SIMD3<Float>(0.80, 0.44, 0.16)
            let dark = SIMD3<Float>(0.36, 0.16, 0.06)
            color = mix(base, dark, stripe)
        case .patchwork:
            let white = SIMD3<Float>(0.90, 0.88, 0.84)
            let orange = SIMD3<Float>(0.82, 0.44, 0.16) * (0.82 + 0.18 * (1 - band(p.x * 12 + n * 3)))
            let black = SIMD3<Float>(0.10, 0.08, 0.07)
            let o = smooth(n, 0.46, 0.58)
            let b = smooth(n2, 0.50, 0.62)
            color = mix(mix(white, orange, o), black, b)
        case .cloud:
            color = SIMD3(0.94, 0.92, 0.89) * (0.96 + 0.08 * n)
        case .mackerel:
            let stripe = sharpBand(p.x * 26 + n * 2.5)
            let base = SIMD3<Float>(0.72, 0.60, 0.46)
            let dark = SIMD3<Float>(0.28, 0.20, 0.14)
            color = mix(base, dark, stripe)
        case .tuxedo:
            let white = SIMD3<Float>(0.93, 0.91, 0.88)
            let black = SIMD3<Float>(0.08, 0.075, 0.08)
            let chest = CatAnatomy.sdEllipse(p, SIMD2(-0.18, 0.04), SIMD2(0.12, 0.08)) < 0
            let blaze = region == .head && abs(p.y) < 0.035 && p.x < -0.5
            let paws = region == .paw
            color = (chest || blaze || paws || region == .innerEar) ? white : black * (0.9 + 0.15 * n)
        case .tortie:
            let orange = SIMD3<Float>(0.78, 0.40, 0.14)
            let black = SIMD3<Float>(0.09, 0.07, 0.065)
            let m = smooth(FurNoise.fbm(p * 4.5 + n2, octaves: 2), 0.42, 0.58)
            color = mix(black, orange, m)
        case .slate:
            let tick = 0.92 + 0.08 * sin(along * 70 + p.y * 40)
            color = SIMD3(0.46, 0.48, 0.52) * tick * (0.94 + 0.1 * n)
        case .brindle:
            let swirl = band(p.x * 8 + sin(p.y * 6) * 2.2 + n * 2)
            let base = SIMD3<Float>(0.62, 0.40, 0.22)
            let dark = SIMD3<Float>(0.28, 0.16, 0.08)
            color = mix(base, dark, swirl)
        case .sealPoint:
            let cream = SIMD3<Float>(0.90, 0.82, 0.70)
            let point = SIMD3<Float>(0.28, 0.18, 0.12)
            color = mix(cream, point, pointMask(p, region))
        case .bluePoint:
            let pale = SIMD3<Float>(0.90, 0.91, 0.93)
            let point = SIMD3<Float>(0.45, 0.50, 0.60)
            var mixed = mix(pale, point, pointMask(p, region) * 0.85)
            if CatAnatomy.sdEllipse(p, SIMD2(-0.16, 0.05), SIMD2(0.10, 0.07)) < 0 {
                mixed = mix(mixed, SIMD3(0.95, 0.95, 0.96), 0.65)
            }
            color = mixed
        case .silverFox:
            let tick = 0.75 + 0.25 * (0.5 + 0.5 * sin(along * 55))
            color = SIMD3(0.62, 0.61, 0.58) * tick * (0.9 + 0.15 * n)
        case .forest:
            let yy = p.y / 0.08
            let dorsal = exp(-(yy * yy)) * smooth(0.35 - p.x, 0, 0.4)
            let base = SIMD3<Float>(0.48, 0.40, 0.30)
            let dark = SIMD3<Float>(0.22, 0.16, 0.12)
            color = mix(base, dark, min(1, dorsal * 0.75 + band(p.x * 10 + n) * 0.25))
        }
        if region == .innerEar {
            color = mix(color, SIMD3(0.74, 0.48, 0.46), coat == .cloud || coat == .sealPoint ? 0.55 : 0.72)
        }
        return color
    }

    static func pointMask(_ p: SIMD2<Float>, _ region: CatRegion) -> Float {
        var m: Float = 0
        if region == .ear || region == .innerEar || region == .tail || region == .paw { m = 1 }
        if region == .head && p.x < -0.60 { m = max(m, smooth(-0.60 - p.x, 0, 0.08)) }
        return m
    }

    static func band(_ x: Float) -> Float {
        let s = sin(x) * 0.5 + 0.5
        return smooth(s, 0.42, 0.62)
    }

    static func sharpBand(_ x: Float) -> Float {
        let s = abs(sin(x))
        return smooth(s, 0.72, 0.9)
    }

    static func smooth(_ v: Float, _ a: Float, _ b: Float) -> Float {
        let t = min(1, max(0, (v - a) / max(1e-4, b - a)))
        return t * t * (3 - 2 * t)
    }

    static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a * (1 - t) + b * t
    }
}
