import CoreGraphics
import simd

enum CatLayout {
    static func cushionRect(in size: CGSize) -> CGRect {
        let wide = size.width > size.height * 1.05
        let marginX = wide ? max(28, (size.width - size.height * 0.78) / 2) : 16
        let top = wide ? size.height * 0.08 : size.height * 0.145
        let bottom = wide ? size.height * 0.08 : size.height * 0.02
        return CGRect(x: marginX, y: top, width: max(1, size.width - marginX * 2), height: max(1, size.height - top - bottom))
    }

    static func center(in size: CGSize) -> SIMD2<Float> {
        let r = cushionRect(in: size)
        return SIMD2(Float(r.minX + r.width * 0.48), Float(r.minY + r.height * 0.42))
    }

    /// Points (or pixels, if `size` is in pixels) per local unit.
    static func scale(in size: CGSize, catSize: Float) -> Float {
        let r = cushionRect(in: size)
        return Float(min(r.width, r.height)) * 0.50 * catSize
    }

    static func toLocal(_ point: CGPoint, in size: CGSize, catSize: Float) -> SIMD2<Float> {
        let c = center(in: size)
        let s = scale(in: size, catSize: catSize)
        return SIMD2((Float(point.x) - c.x) / s, (Float(point.y) - c.y) / s)
    }

    static func toView(_ local: SIMD2<Float>, in size: CGSize, catSize: Float) -> CGPoint {
        let c = center(in: size)
        let s = scale(in: size, catSize: catSize)
        return CGPoint(x: CGFloat(c.x + local.x * s), y: CGFloat(c.y + local.y * s))
    }

    static func windowRect(in size: CGSize) -> CGRect {
        CGRect(x: 0, y: 0, width: size.width * 0.52, height: size.height * 0.21)
    }
}
