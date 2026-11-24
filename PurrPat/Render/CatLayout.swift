import CoreGraphics
import simd

enum CatLayout {
    /// Plate pixels. Every coat and the empty cushion share this frame.
    static let plateWidth: Float = 720
    static let plateHeight: Float = 1280

    /// Aspect-fill UV for a point in a view. UV origin is the top-left of the plate, y down.
    static func uv(_ point: CGPoint, in size: CGSize, catSize: Float) -> SIMD2<Float> {
        let fit = fitRect(in: size, catSize: catSize)
        let u = (Float(point.x) - Float(fit.minX)) / max(Float(fit.width), 1)
        let v = (Float(point.y) - Float(fit.minY)) / max(Float(fit.height), 1)
        return SIMD2(u, v)
    }

    static func point(_ uv: SIMD2<Float>, in size: CGSize, catSize: Float) -> CGPoint {
        let fit = fitRect(in: size, catSize: catSize)
        return CGPoint(
            x: fit.minX + CGFloat(uv.x) * fit.width,
            y: fit.minY + CGFloat(uv.y) * fit.height
        )
    }

    /// Points per unit of plate UV, x then y. Stroke speed is measured in points.
    static func pointsPerUV(in size: CGSize, catSize: Float) -> SIMD2<Float> {
        let fit = fitRect(in: size, catSize: catSize)
        return SIMD2(Float(fit.width), Float(fit.height))
    }

    /// Shared silhouette of every plate, in UV. Head at the top, tail curl at the bottom.
    static let catMinX: CGFloat = 0.169
    static let catMaxX: CGFloat = 0.778
    static let catMinY: CGFloat = 0.172
    static let catMaxY: CGFloat = 0.843

    /// Places the plate so the cat has about 13% of cushion on each side, the tail clears the coat bar, and the linen still covers the screen.
    static func fitRect(in size: CGSize, catSize: Float) -> CGRect {
        let zoom = CGFloat(min(1.2, max(0.85, catSize)))
        let margin: CGFloat = 0.135
        let catW = catMaxX - catMinX
        let catH = catMaxY - catMinY
        var scale = (size.width * (1 - 2 * margin) * zoom) / (CGFloat(plateWidth) * catW)
        let verticalScale = (size.height * 0.74) / (CGFloat(plateHeight) * catH)
        scale = min(scale, verticalScale)
        var dw = CGFloat(plateWidth) * scale
        var dh = CGFloat(plateHeight) * scale
        let catCenterX = (catMinX + catMaxX) / 2
        var ox = size.width / 2 - catCenterX * dw
        var oy = size.height * 0.78 - catMaxY * dh
        let minHead = size.height * 0.06
        if oy + catMinY * dh < minHead {
            oy += minHead - (oy + catMinY * dh)
        }
        if oy + dh < size.height {
            let room = size.height * 0.86 - (oy + catMaxY * dh)
            let need = size.height - (oy + dh)
            oy += min(need, max(0, room))
        }
        if oy > 0 { oy = 0 }
        let gapTop = max(0, oy)
        let gapBottom = max(0, size.height - (oy + dh))
        let gapLeft = max(0, ox)
        let gapRight = max(0, size.width - (ox + dw))
        let extra = max(1, 1 + (gapTop + gapBottom) / dh, 1 + (gapLeft + gapRight) / dw)
        if extra > 1.001 {
            dw *= extra
            dh *= extra
            ox = size.width / 2 - catCenterX * dw
            oy = size.height * 0.82 - catMaxY * dh
            if oy > 0 { oy = 0 }
            if oy + dh < size.height { oy = size.height - dh }
        }
        let headY = oy + catMinY * dh
        if headY < minHead {
            oy += minHead - headY
        }
        return CGRect(x: ox, y: oy, width: max(dw, 1), height: max(dh, 1))
    }
}
