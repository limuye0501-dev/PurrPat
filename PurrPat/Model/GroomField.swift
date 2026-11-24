import Foundation
import simd

/// A groom direction map. Touches push the fur; a damped spring carries it home.
final class GroomField {
    let width: Int
    let height: Int
    let origin: SIMD2<Float>
    let span: SIMD2<Float>

    private var flow: [SIMD2<Float>]
    private var velocity: [SIMD2<Float>]
    private var part: [Float]
    private var partVelocity: [Float]

    init(width: Int = 96, height: Int = 64) {
        self.width = width
        self.height = height
        origin = SIMD2(-0.95, -0.58)
        span = SIMD2(2.05, 1.16)
        let n = width * height
        flow = Array(repeating: .zero, count: n)
        velocity = Array(repeating: .zero, count: n)
        part = Array(repeating: 0, count: n)
        partVelocity = Array(repeating: 0, count: n)
    }

    /// A copy safe to sample on a background queue while touches keep writing this one.
    func snapshot() -> GroomField {
        let copy = GroomField(width: width, height: height)
        copy.flow = flow
        copy.part = part
        return copy
    }

    func clear() {
        let n = width * height
        flow = Array(repeating: .zero, count: n)
        velocity = Array(repeating: .zero, count: n)
        part = Array(repeating: 0, count: n)
        partVelocity = Array(repeating: 0, count: n)
    }

    func stamp(local: SIMD2<Float>, direction: SIMD2<Float>, radius: Float, amount: Float) {
        let len = simd_length(direction)
        guard len > 1e-4, radius > 0, amount > 0 else { return }
        let dir = direction / len
        let uv = (local - origin) / span
        let cx = uv.x * Float(width - 1)
        let cy = uv.y * Float(height - 1)
        let rx = radius / span.x * Float(width)
        let ry = radius / span.y * Float(height)
        let minX = max(0, Int(floor(cx - rx * 2)))
        let maxX = min(width - 1, Int(ceil(cx + rx * 2)))
        let minY = max(0, Int(floor(cy - ry * 2)))
        let maxY = min(height - 1, Int(ceil(cy + ry * 2)))
        guard minX <= maxX, minY <= maxY else { return }
        let sigmaX = max(rx, 0.8)
        let sigmaY = max(ry, 0.8)
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = (Float(x) - cx) / sigmaX
                let dy = (Float(y) - cy) / sigmaY
                let w = exp(-(dx * dx + dy * dy) * 0.5) * amount
                if w < 0.02 { continue }
                let i = y * width + x
                let target = dir * min(1, amount)
                flow[i] += (target - flow[i]) * min(1, w)
                part[i] += (1 - part[i]) * min(1, w)
                velocity[i] *= 1 - min(1, w)
                partVelocity[i] *= 1 - min(1, w)
            }
        }
    }

    func spring(dt: Float) {
        let dt = min(max(dt, 0), 1.0 / 20)
        let k: Float = 7.5
        let c: Float = 5.0
        for i in flow.indices {
            let acc = -k * flow[i] - c * velocity[i]
            velocity[i] += acc * dt
            flow[i] += velocity[i] * dt
            let ap = -k * part[i] - c * partVelocity[i]
            partVelocity[i] += ap * dt
            part[i] = max(0, part[i] + partVelocity[i] * dt)
        }
    }

    func sample(local: SIMD2<Float>) -> (flow: SIMD2<Float>, part: Float) {
        let uv = (local - origin) / span
        let x = uv.x * Float(width - 1)
        let y = uv.y * Float(height - 1)
        if x < 0 || y < 0 || x > Float(width - 1) || y > Float(height - 1) {
            return (.zero, 0)
        }
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = min(width - 1, x0 + 1)
        let y1 = min(height - 1, y0 + 1)
        let tx = x - Float(x0)
        let ty = y - Float(y0)
        func at(_ ix: Int, _ iy: Int) -> (SIMD2<Float>, Float) {
            let i = iy * width + ix
            return (flow[i], part[i])
        }
        let a = at(x0, y0)
        let b = at(x1, y0)
        let c = at(x0, y1)
        let d = at(x1, y1)
        let top = a.0 * (1 - tx) + b.0 * tx
        let bottom = c.0 * (1 - tx) + d.0 * tx
        let flowV = top * (1 - ty) + bottom * ty
        let partTop = a.1 * (1 - tx) + b.1 * tx
        let partBottom = c.1 * (1 - tx) + d.1 * tx
        let partV = partTop * (1 - ty) + partBottom * ty
        return (flowV, partV)
    }

    /// RGBA8, flow packed from -1...1 into R and G, part in B.
    func rgbaBytes() -> [UInt8] {
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for i in flow.indices {
            let o = i * 4
            out[o] = Self.unit(flow[i].x)
            out[o + 1] = Self.unit(flow[i].y)
            out[o + 2] = Self.pack(part[i])
            out[o + 3] = 255
        }
        return out
    }

    private static func unit(_ v: Float) -> UInt8 {
        let n = Int((min(1, max(-1, v)) * 0.5 + 0.5) * 255)
        return UInt8(clamping: n)
    }

    private static func pack(_ v: Float) -> UInt8 {
        UInt8(clamping: Int(min(1, max(0, v)) * 255))
    }
}
