import CoreGraphics
import simd

/// Packed as float4s so the Swift layout matches CatScene.metal exactly.
struct CatUniforms {
    var resTimeZoom = SIMD4<Float>(repeating: 0)
    var motion = SIMD4<Float>(repeating: 0)
    var tailScene = SIMD4<Float>(repeating: 0)
    var groomRect = SIMD4<Float>(repeating: 0)
    var plateRect = SIMD4<Float>(repeating: 0)

    @MainActor
    static func make(bounds: CGSize, contentScale: CGFloat, settings: AppSettings, session: PetSession) -> CatUniforms {
        let s = Float(contentScale)
        let pose = session.pose
        var u = CatUniforms()
        u.resTimeZoom = SIMD4(Float(bounds.width) * s, Float(bounds.height) * s, Float(session.time), settings.catSize)
        u.motion = SIMD4(pose.breath, pose.earL, pose.earR, pose.chub)
        u.tailScene = SIMD4(
            pose.tailStretch,
            pose.tailSway,
            settings.rain ? 1 : 0,
            settings.scene == .night ? 1 : 0
        )
        u.groomRect = SIMD4(session.groom.origin.x, session.groom.origin.y, session.groom.span.x, session.groom.span.y)
        let fit = CatLayout.fitRect(in: bounds, catSize: settings.catSize)
        u.plateRect = SIMD4(Float(fit.minX) * s, Float(fit.minY) * s, Float(fit.width) * s, Float(fit.height) * s)
        return u
    }
}
