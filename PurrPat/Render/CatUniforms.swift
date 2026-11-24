import simd

/// Packed as float4s so the Swift layout matches CatScene.metal exactly.
struct CatUniforms {
    var resCenter = SIMD4<Float>(repeating: 0)
    var scaleTimeChubRain = SIMD4<Float>(repeating: 0)
    var breathEarStretch = SIMD4<Float>(repeating: 0)
    var swayDelightHappyScene = SIMD4<Float>(repeating: 0)
    var groomRect = SIMD4<Float>(repeating: 0)
    var cushion = SIMD4<Float>(repeating: 0)
    var extras = SIMD4<Float>(repeating: 0)

    @MainActor
    static func make(bounds: CGSize, contentScale: CGFloat, settings: AppSettings, session: PetSession) -> CatUniforms {
        let s = Float(contentScale)
        let center = CatLayout.center(in: bounds)
        let scale = CatLayout.scale(in: bounds, catSize: settings.catSize)
        let cush = CatLayout.cushionRect(in: bounds)
        let pose = session.pose
        var u = CatUniforms()
        u.resCenter = SIMD4(Float(bounds.width) * s, Float(bounds.height) * s, center.x * s, center.y * s)
        u.scaleTimeChubRain = SIMD4(scale * s, Float(session.time), pose.widthScale, settings.rain && settings.scene == .night ? 1 : (settings.rain ? 1 : 0))
        u.breathEarStretch = SIMD4(pose.breath, pose.earL, pose.earR, pose.tailStretch)
        u.swayDelightHappyScene = SIMD4(pose.tailSway, pose.delight, Float(session.happiness), settings.scene == .night ? 1 : 0)
        u.groomRect = SIMD4(session.groom.origin.x, session.groom.origin.y, session.groom.span.x, session.groom.span.y)
        u.cushion = SIMD4(Float(cush.minX) * s, Float(cush.minY) * s, Float(cush.width) * s, Float(cush.height) * s)
        u.extras = SIMD4(Float(settings.coat.rawValue), Float(pose.delightKind), settings.catSize, pose.furLength(settings.coat))
        return u
    }
}

private extension CatPose {
    func furLength(_ coat: Coat) -> Float { coat.furLength }
}
