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

    /// Places the plate so the cat has about 13% of cushion on each side and the tail sits above the coat bar.
    static func fitRect(in size: CGSize, catSize: Float) -> CGRect {
        let zoom = CGFloat(min(1.2, max(0.85, catSize)))
        let margin: CGFloat = 0.135
        let catW = catMaxX - catMinX
        let catH = catMaxY - catMinY
        var scale = (size.width * (1 - 2 * margin) * zoom) / (CGFloat(plateWidth) * catW)
        // On a wide screen the width rule would push the head or tail off. Fit the cat vertically too.
        let maxCatHeight = size.height * 0.74
        let verticalScale = maxCatHeight / (CGFloat(plateHeight) * catH)
        scale = min(scale, verticalScale)
        let dw = CGFloat(plateWidth) * scale
        let dh = CGFloat(plateHeight) * scale
        let catCenterX = (catMinX + catMaxX) / 2
        let ox = size.width / 2 - catCenterX * dw
        var oy = size.height * 0.78 - catMaxY * dh
        let headY = oy + catMinY * dh
        let minHead = size.height * 0.07
        if headY < minHead {
            oy += minHead - headY
        }
        return CGRect(x: ox, y: oy, width: max(dw, 1), height: max(dh, 1))
    }
}
