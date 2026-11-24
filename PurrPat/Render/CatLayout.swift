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

    static func fitRect(in size: CGSize, catSize: Float) -> CGRect {
        let zoom = CGFloat(min(1.2, max(0.85, catSize)))
        let scale = max(size.width / CGFloat(plateWidth), size.height / CGFloat(plateHeight)) * zoom
        let dw = CGFloat(plateWidth) * scale
        let dh = CGFloat(plateHeight) * scale
        return CGRect(x: (size.width - dw) / 2, y: (size.height - dh) / 2, width: max(dw, 1), height: max(dh, 1))
    }
}
