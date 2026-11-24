import CoreGraphics
import simd
import UIKit

enum ScenePainter {
    static func render(
        bounds: CGSize,
        scale: CGFloat,
        coat: Coat,
        scene: RoomScene,
        pose: CatPose,
        groom: GroomField,
        rain: Float,
        time: Float,
        catSize: Float,
        interactive: Bool,
        drawCat: Bool = true
    ) -> UIImage {
        var pixelScale = max(scale, 1)
        var width = max(1, Int((bounds.width * pixelScale).rounded()))
        var height = max(1, Int((bounds.height * pixelScale).rounded()))
        let cap = interactive ? 1000 : 1440
        let longSide = max(width, height)
        if longSide > cap {
            let fit = Double(cap) / Double(longSide)
            width = max(1, Int((Double(width) * fit).rounded()))
            height = max(1, Int((Double(height) * fit).rounded()))
            pixelScale = bounds.height > 1 ? CGFloat(height) / bounds.height : pixelScale
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let library = PlateLibrary.shared
        let cushion = library.cushion
        let cat = library.cat(coat)
        let mask = library.mask(coat)
        let maps = groom.packed()
        let night = scene == .night
        let zoom = min(1.2, max(0.85, catSize))
        let fit = max(Float(width) / CatLayout.plateWidth, Float(height) / CatLayout.plateHeight) * zoom
        let dw = CatLayout.plateWidth * fit
        let dh = CatLayout.plateHeight * fit
        let ox = (Float(width) - dw) * 0.5
        let oy = (Float(height) - dh) * 0.5

        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            cushion.rgba.withUnsafeBufferPointer { cushionPx in
                cat.rgba.withUnsafeBufferPointer { catPx in
                    mask.rgba.withUnsafeBufferPointer { maskPx in
                        maps.flowX.withUnsafeBufferPointer { fx in
                            maps.flowY.withUnsafeBufferPointer { fy in
                                maps.part.withUnsafeBufferPointer { part in
                                    fill(
                                        base: base, width: width, height: height,
                                        cushion: cushionPx.baseAddress, cushionW: cushion.width, cushionH: cushion.height,
                                        cat: catPx.baseAddress, catW: cat.width, catH: cat.height,
                                        mask: maskPx.baseAddress, maskW: mask.width, maskH: mask.height,
                                        flowX: fx.baseAddress, flowY: fy.baseAddress, part: part.baseAddress,
                                        groomW: maps.width, groomH: maps.height,
                                        ox: ox, oy: oy, dw: dw, dh: dh,
                                        pose: pose, night: night, rain: rain > 0.5, time: time,
                                        drawCat: drawCat
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else {
            return UIImage()
        }
        return UIImage(cgImage: image, scale: pixelScale, orientation: .up)
    }
}

private func fill(
    base: UnsafeMutablePointer<UInt8>,
    width: Int,
    height: Int,
    cushion: UnsafePointer<UInt8>?,
    cushionW: Int,
    cushionH: Int,
    cat: UnsafePointer<UInt8>?,
    catW: Int,
    catH: Int,
    mask: UnsafePointer<UInt8>?,
    maskW: Int,
    maskH: Int,
    flowX: UnsafePointer<Float>?,
    flowY: UnsafePointer<Float>?,
    part: UnsafePointer<Float>?,
    groomW: Int,
    groomH: Int,
    ox: Float,
    oy: Float,
    dw: Float,
    dh: Float,
    pose: CatPose,
    night: Bool,
    rain: Bool,
    time: Float,
    drawCat: Bool
) {
    let breath = pose.breath
    let earL = pose.earL
    let earR = pose.earR
    let chub = pose.chub
    let stretch = pose.tailStretch
    let sway = pose.tailSway
    let wide = 0.96 + chub * 0.08
    for y in 0..<height {
        let row = y * width
        let fy = Float(y) + 0.5
        for x in 0..<width {
            let fx = Float(x) + 0.5
            let u = (fx - ox) / dw
            let v = (fy - oy) / dh
            var rgb = sampleRGB(cushion, cushionW, cushionH, u, v)
            if night { rgb = grade(rgb) }
            if drawCat {
                let groom = sampleGroom(flowX, flowY, part, groomW, groomH, u, v)
                let warped = warp(
                    u, v, breath: breath, earL: earL, earR: earR, chubScale: wide,
                    stretch: stretch, sway: sway, flow: groom.0, part: groom.1
                )
                var fur = sampleRGB(cat, catW, catH, warped.x, warped.y)
                let maskV = sampleR(mask, maskW, maskH, warped.x, warped.y)
                let detail = hash2(x &* 3, y &* 5)
                let strand = hash2(x, y * 3 + 7)
                let grain = 0.945 + 0.04 * detail + 0.035 * smooth(strand, 0.28, 0.75)
                fur *= grain
                let press = min(max(groom.1, 0), 1)
                fur *= 1 - 0.22 * press
                let sheen = night ? SIMD3<Float>(0.62, 0.70, 0.82) : SIMD3<Float>(1, 0.96, 0.88)
                fur += sheen * press * press * 0.14
                if night { fur = grade(fur) }
                let alpha = smooth(maskV, 0.12, 0.62)
                let occ = (
                    sampleR(mask, maskW, maskH, u, v + 0.007)
                        + sampleR(mask, maskW, maskH, u + 0.004, v + 0.009)
                        + sampleR(mask, maskW, maskH, u - 0.004, v + 0.008)
                ) * 0.34
                let shade = min(max(occ - alpha, 0), 1)
                rgb *= 1 - shade * (night ? 0.42 : 0.26)
                rgb = rgb * (1 - alpha) + fur * alpha
            }
            if rain {
                let drop = fract(fy * 0.016 - time * 0.32 + fx * 0.008)
                var streak = smooth(drop, 0, 0.045) * (1 - smooth(drop, 0.045, 0.15))
                let column = abs(fract(fx * 0.028) - 0.5)
                streak *= 1 - smooth(column, 0, 0.42)
                rgb += streak * (night ? 0.09 : 0.06)
            }
            rgb = simd_clamp(rgb, SIMD3(repeating: 0), SIMD3(repeating: 1))
            let o = (row + x) * 4
            base[o] = UInt8(rgb.x * 255)
            base[o + 1] = UInt8(rgb.y * 255)
            base[o + 2] = UInt8(rgb.z * 255)
            base[o + 3] = 255
        }
    }
}

private func warp(
    _ u: Float, _ v: Float,
    breath: Float, earL: Float, earR: Float, chubScale: Float,
    stretch: Float, sway: Float, flow: SIMD2<Float>, part: Float
) -> SIMD2<Float> {
    var x = 0.48 + (u - 0.48) / chubScale
    var y = v
    let dx = x - 0.48
    let dy = y - 0.46
    let bw = smooth(length2(dx / 0.20, dy / 0.18), 1.35, 0.2)
    let breathScale = 1 - breath * 0.018 * bw
    x = 0.48 + dx * breathScale
    y = 0.46 + dy * breathScale
    y += earL * earFalloff(x, y, 0.385, 0.218) * 0.012
    y += earR * earFalloff(x, y, 0.575, 0.216) * 0.012
    let tail = tailShift(x, y, stretch: stretch, sway: sway)
    x += tail.x
    y += tail.y
    x -= flow.x * part * 0.014
    y -= flow.y * part * 0.014
    return SIMD2(x, y)
}

private func tailShift(_ x: Float, _ y: Float, stretch: Float, sway: Float) -> SIMD2<Float> {
    let p = SIMD2(x, y)
    let base = SIMD2<Float>(0.48, 0.63)
    let mid = SIMD2<Float>(0.40 - sway * 0.25, 0.72)
    let curl = SIMD2<Float>(0.31 - sway * 0.40, 0.775)
    let tip = SIMD2<Float>(0.255 - sway * 0.20 - stretch * 0.03, 0.71 - stretch * 0.025)
    let d0 = CatAnatomy.sdSegment(p, base, mid)
    let d1 = CatAnatomy.sdSegment(p, mid, curl)
    let d2 = CatAnatomy.sdSegment(p, curl, tip)
    let d = min(d0, min(d1, d2))
    let along: Float = d0 <= d1 && d0 <= d2 ? 0.25 : (d1 <= d2 ? 0.6 : 1)
    let tw = smooth(d, 0.055, 0.01)
    return SIMD2(sway * tw * along * 0.65 + stretch * tw * along * 0.035, stretch * tw * along * 0.02)
}

private func earFalloff(_ x: Float, _ y: Float, _ cx: Float, _ cy: Float) -> Float {
    let d = length2((x - cx) / 0.05, (y - cy) / 0.042)
    return smooth(d, 1.05, 0.2)
}

private func sampleGroom(
    _ flowX: UnsafePointer<Float>?,
    _ flowY: UnsafePointer<Float>?,
    _ part: UnsafePointer<Float>?,
    _ width: Int,
    _ height: Int,
    _ u: Float,
    _ v: Float
) -> (SIMD2<Float>, Float) {
    guard let flowX, let flowY, let part, width > 1, height > 1 else { return (.zero, 0) }
    let x = min(max(u, 0), 1) * Float(width - 1)
    let y = min(max(v, 0), 1) * Float(height - 1)
    let x0 = Int(x)
    let y0 = Int(y)
    let x1 = min(width - 1, x0 + 1)
    let y1 = min(height - 1, y0 + 1)
    let tx = x - Float(x0)
    let ty = y - Float(y0)
    func at(_ ix: Int, _ iy: Int) -> SIMD3<Float> {
        let i = iy * width + ix
        return SIMD3(flowX[i], flowY[i], part[i])
    }
    let a = at(x0, y0)
    let b = at(x1, y0)
    let c = at(x0, y1)
    let d = at(x1, y1)
    let top = a * (1 - tx) + b * tx
    let bot = c * (1 - tx) + d * tx
    let m = top * (1 - ty) + bot * ty
    return (SIMD2(m.x, m.y), m.z)
}

private func sampleRGB(_ px: UnsafePointer<UInt8>?, _ width: Int, _ height: Int, _ u: Float, _ v: Float) -> SIMD3<Float> {
    guard let px, width > 1, height > 1 else { return SIMD3(0.84, 0.77, 0.68) }
    let x = min(max(u, 0), 1) * Float(width - 1)
    let y = min(max(v, 0), 1) * Float(height - 1)
    let x0 = Int(x)
    let y0 = Int(y)
    let x1 = min(width - 1, x0 + 1)
    let y1 = min(height - 1, y0 + 1)
    let tx = x - Float(x0)
    let ty = y - Float(y0)
    func at(_ ix: Int, _ iy: Int) -> SIMD3<Float> {
        let i = (iy * width + ix) * 4
        return SIMD3(Float(px[i]) / 255, Float(px[i + 1]) / 255, Float(px[i + 2]) / 255)
    }
    let a = at(x0, y0)
    let b = at(x1, y0)
    let c = at(x0, y1)
    let d = at(x1, y1)
    let top = a * (1 - tx) + b * tx
    let bot = c * (1 - tx) + d * tx
    return top * (1 - ty) + bot * ty
}

private func sampleR(_ px: UnsafePointer<UInt8>?, _ width: Int, _ height: Int, _ u: Float, _ v: Float) -> Float {
    guard let px, width > 1, height > 1 else { return 0 }
    let x = min(max(u, 0), 1) * Float(width - 1)
    let y = min(max(v, 0), 1) * Float(height - 1)
    let x0 = Int(x)
    let y0 = Int(y)
    let x1 = min(width - 1, x0 + 1)
    let y1 = min(height - 1, y0 + 1)
    let tx = x - Float(x0)
    let ty = y - Float(y0)
    func at(_ ix: Int, _ iy: Int) -> Float {
        Float(px[(iy * width + ix) * 4]) / 255
    }
    let top = at(x0, y0) * (1 - tx) + at(x1, y0) * tx
    let bot = at(x0, y1) * (1 - tx) + at(x1, y1) * tx
    return top * (1 - ty) + bot * ty
}

private func grade(_ c: SIMD3<Float>) -> SIMD3<Float> {
    simd_clamp(c * SIMD3<Float>(0.457, 0.643, 0.917) + SIMD3<Float>(-0.020, -0.018, 0.004), SIMD3(repeating: 0), SIMD3(repeating: 1))
}

private func hash2(_ x: Int, _ y: Int) -> Float {
    var n = UInt32(bitPattern: x &* 374761393 &+ y &* 668265263)
    n = (n ^ (n >> 13)) &* 1274126177
    return Float(n & 0xFFFFFF) / Float(0xFFFFFF)
}

private func smooth(_ x: Float, _ a: Float, _ b: Float) -> Float {
    let t = min(max((x - a) / (b - a + 1e-5), 0), 1)
    return t * t * (3 - 2 * t)
}

private func fract(_ x: Float) -> Float { x - floor(x) }

private func length2(_ x: Float, _ y: Float) -> Float { sqrt(x * x + y * y) }
