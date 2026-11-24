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
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: bounds, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            drawRoom(cg, bounds: bounds, scene: scene, time: time)
            if drawCat, let cat = catImage(bounds: bounds, coat: coat, scene: scene, pose: pose, groom: groom, catSize: catSize, interactive: interactive) {
                cg.saveGState()
                cg.setShadow(
                    offset: CGSize(width: 0, height: 14),
                    blur: 22,
                    color: UIColor.black.withAlphaComponent(scene == .day ? 0.20 : 0.40).cgColor
                )
                cat.image.draw(in: cat.rect)
                cg.restoreGState()
            }
            if drawCat {
                drawFace(cg, bounds: bounds, pose: pose, catSize: catSize, scene: scene)
            }
            if rain > 0.4 {
                drawRain(cg, bounds: bounds, time: time, night: scene == .night)
            }
        }
    }

    private static func drawRoom(_ cg: CGContext, bounds: CGSize, scene: RoomScene, time: Float) {
        let day = scene == .day
        let top = day ? UIColor(red: 0.91, green: 0.84, blue: 0.75, alpha: 1) : UIColor(red: 0.12, green: 0.15, blue: 0.24, alpha: 1)
        let bottom = day ? UIColor(red: 0.84, green: 0.75, blue: 0.64, alpha: 1) : UIColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1)
        let colors = [top.cgColor, bottom.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: bounds.height), options: [])
        }

        let window = CatLayout.windowRect(in: bounds)
        cg.saveGState()
        let winPath = UIBezierPath(roundedRect: window, cornerRadius: 18)
        winPath.addClip()
        let skyTop = day ? UIColor(red: 1, green: 0.96, blue: 0.90, alpha: 1) : UIColor(red: 0.10, green: 0.14, blue: 0.28, alpha: 1)
        let skyBot = day ? UIColor(red: 1, green: 0.86, blue: 0.70, alpha: 1) : UIColor(red: 0.05, green: 0.07, blue: 0.14, alpha: 1)
        if let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [skyTop.cgColor, skyBot.cgColor] as CFArray, locations: [0, 1]) {
            cg.drawLinearGradient(sky, start: window.origin, end: CGPoint(x: window.minX, y: window.maxY), options: [])
        }
        if !day {
            cg.setFillColor(UIColor(red: 0.93, green: 0.94, blue: 0.88, alpha: 0.95).cgColor)
            cg.fillEllipse(in: CGRect(x: window.maxX - 92, y: 28, width: 54, height: 54))
        }
        cg.setFillColor((day ? UIColor(white: 0.98, alpha: 0.55) : UIColor(red: 0.65, green: 0.70, blue: 0.78, alpha: 0.28)).cgColor)
        let folds = 7
        let foldW = min(72, window.width * 0.22) / CGFloat(folds)
        for i in 0..<folds {
            let shade: CGFloat = i % 2 == 0 ? 1 : 0.82
            cg.setAlpha(shade)
            cg.fill(CGRect(x: window.minX + CGFloat(i) * foldW, y: window.minY, width: foldW + 0.5, height: window.height))
        }
        cg.restoreGState()

        let cushion = CatLayout.cushionRect(in: bounds)
        let cushColor = day
            ? UIColor(red: 0.84, green: 0.77, blue: 0.67, alpha: 1)
            : UIColor(red: 0.24, green: 0.27, blue: 0.36, alpha: 1)
        let cushPath = UIBezierPath(roundedRect: cushion, cornerRadius: 36)
        cg.saveGState()
        cg.addPath(cushPath.cgPath)
        cg.setFillColor(cushColor.cgColor)
        cg.fillPath()
        cg.addPath(cushPath.cgPath)
        cg.clip()
        drawWeave(cg, rect: cushion, day: day)
        drawRays(cg, window: window, cushion: cushion, day: day, time: time)
        cg.restoreGState()
        cg.addPath(cushPath.cgPath)
        cg.setStrokeColor((day ? UIColor(red: 0.72, green: 0.64, blue: 0.52, alpha: 0.45) : UIColor(white: 1, alpha: 0.08)).cgColor)
        cg.setLineWidth(10)
        cg.strokePath()
    }

    private static func drawWeave(_ cg: CGContext, rect: CGRect, day: Bool) {
        cg.saveGState()
        cg.setAlpha(day ? 0.07 : 0.05)
        cg.draw(linenTile(day: day), in: rect)
        cg.restoreGState()
    }

    /// A soft irregular linen, generated once. A ruled grid reads as graph paper, not cloth.
    private static func linenTile(day: Bool) -> CGImage {
        let key = day ? "day" : "night"
        if let cached = linenCache[key] { return cached }
        let n = 96
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let p = SIMD2(Float(x) / 9.0, Float(y) / 9.0)
                let v = FurNoise.fbm(p, octaves: 3)
                let thread = 0.5 + 0.5 * sin(Float(x) * 0.85 + v * 2) * sin(Float(y) * 0.8)
                let tone = min(1, max(0, 0.35 + 0.4 * v + 0.25 * thread))
                let o = (y * n + x) * 4
                let b = UInt8(tone * 255)
                px[o] = b
                px[o + 1] = b
                px[o + 2] = b
                px[o + 3] = 255
            }
        }
        let data = Data(px) as CFData
        let provider = CGDataProvider(data: data)!
        let info = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
        let image = CGImage(
            width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )!
        linenCache[key] = image
        return image
    }

    private static var linenCache: [String: CGImage] = [:]

    private static func drawRays(_ cg: CGContext, window: CGRect, cushion: CGRect, day: Bool, time: Float) {
        cg.saveGState()
        cg.setAlpha(day ? 0.10 : 0.06)
        cg.setFillColor((day ? UIColor(red: 1, green: 0.95, blue: 0.82, alpha: 1) : UIColor(red: 0.75, green: 0.82, blue: 1, alpha: 1)).cgColor)
        let drift = CGFloat(sin(time * 0.15)) * 12
        let beams: [(CGFloat, CGFloat)] = [(18, 54), (70, 36), (120, 70)]
        for (x, width) in beams {
            let path = UIBezierPath()
            let x0 = window.minX + x + drift
            path.move(to: CGPoint(x: x0, y: window.maxY - 8))
            path.addLine(to: CGPoint(x: x0 + width, y: window.maxY - 8))
            path.addLine(to: CGPoint(x: x0 + width + 160, y: cushion.maxY))
            path.addLine(to: CGPoint(x: x0 + 70, y: cushion.maxY))
            path.close()
            cg.addPath(path.cgPath)
            cg.fillPath()
        }
        cg.restoreGState()
    }

    private struct CatLayer {
        var image: UIImage
        var rect: CGRect
    }

    private static func catImage(
        bounds: CGSize,
        coat: Coat,
        scene: RoomScene,
        pose: CatPose,
        groom: GroomField,
        catSize: Float,
        interactive: Bool
    ) -> CatLayer? {
        let minL = SIMD2<Float>(-0.92, -0.48)
        let maxL = SIMD2<Float>(1.05 + pose.tailStretch * 0.35, 0.48)
        let a = CatLayout.toView(minL, in: bounds, catSize: catSize)
        let b = CatLayout.toView(maxL, in: bounds, catSize: catSize)
        var rect = CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(a.x - b.x), height: abs(a.y - b.y)
        ).insetBy(dx: -6, dy: -6)
        rect = rect.intersection(CGRect(origin: .zero, size: bounds).insetBy(dx: -20, dy: -20))
        guard rect.width > 4, rect.height > 4 else { return nil }
        var w = Int(rect.width * (interactive ? 1.25 : 2))
        var h = Int(rect.height * (interactive ? 1.25 : 2))
        // Keep the cat buffer small enough that a debug simulator finishes a frame
        // in a couple of seconds. The room behind it is drawn at full resolution.
        let cap = interactive ? 70_000 : 260_000
        if w * h > cap {
            let f = sqrt(Double(cap) / Double(w * h))
            w = max(8, Int(Double(w) * f))
            h = max(8, Int(Double(h) * f))
        }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let center = CatLayout.center(in: bounds)
        let sc = CatLayout.scale(in: bounds, catSize: catSize)
        let octaves = interactive ? 2 : 3
        let day = scene == .day
        pixels.withUnsafeMutableBytes { raw in
            let buf = raw.bindMemory(to: UInt8.self)
            for y in 0..<h {
                for x in 0..<w {
                    let px = Float(rect.minX) + (Float(x) + 0.5) / Float(w) * Float(rect.width)
                    let py = Float(rect.minY) + (Float(y) + 0.5) / Float(h) * Float(rect.height)
                    let local = SIMD2((px - center.x) / sc, (py - center.y) / sc)
                    let shaded = shade(local: local, coat: coat, sceneDay: day, pose: pose, groom: groom, octaves: octaves)
                    let alpha = min(1, max(0, shaded.a))
                    let o = (y * w + x) * 4
                    let ia = UInt8(alpha * 255)
                    buf[o] = UInt8(min(255, max(0, shaded.rgb.z * alpha * 255)))
                    buf[o + 1] = UInt8(min(255, max(0, shaded.rgb.y * alpha * 255)))
                    buf[o + 2] = UInt8(min(255, max(0, shaded.rgb.x * alpha * 255)))
                    buf[o + 3] = ia
                }
            }
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let info = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
        guard let image = CGImage(
            width: w, height: h,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: info,
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        ) else { return nil }
        return CatLayer(image: UIImage(cgImage: image), rect: rect)
    }

    private static func shade(
        local: SIMD2<Float>,
        coat: Coat,
        sceneDay: Bool,
        pose: CatPose,
        groom: GroomField,
        octaves: Int
    ) -> (rgb: SIMD3<Float>, a: Float) {
        let sample = CatAnatomy.sample(local, pose: pose)
        let fringe = 0.018 * coat.furLength
        if sample.sdf > fringe { return (.zero, 0) }
        let groomed = groom.sample(local: local)
        var fur = sample.grain + groomed.flow * 1.2
        let fl = simd_length(fur)
        if fl > 1e-4 { fur /= fl }
        let along = simd_dot(local, fur)
        let across = simd_dot(local, SIMD2(-fur.y, fur.x))
        let clump = FurNoise.fbm(local * 3.1, octaves: octaves)
        // Coarse enough to survive the screenshot scale, fine enough to read as hair.
        let strand = FurNoise.value(SIMD2(along * 5.5, across * 16))
        let fine = FurNoise.value(SIMD2(along * 9, across * 28))
        let fiber = 0.72 + 0.20 * strand + 0.12 * fine + 0.08 * clump
        var alb = CoatColor.albedo(coat, p: local, region: sample.region, along: along)
        alb *= 0.84 + 0.28 * clump
        let amb: SIMD3<Float> = sceneDay ? SIMD3(0.48, 0.40, 0.34) : SIMD3(0.22, 0.26, 0.40)
        let key: SIMD3<Float> = sceneDay ? SIMD3(1.02, 0.94, 0.82) : SIMD3(0.52, 0.62, 0.90)
        let inside = CoatColor.smooth(-sample.sdf, 0, 0.06)
        let yy = local.y / (0.15 * pose.widthScale)
        let xx = (local.x - 0.02) / 0.42
        let spine = exp(-(yy * yy)) * exp(-(xx * xx))
        var col = alb * (amb + key * (0.34 + 0.5 * inside)) * fiber
        let sheen: SIMD3<Float> = sceneDay ? SIMD3(1, 0.94, 0.82) : SIMD3(0.72, 0.80, 1)
        // Hair catches light on the crests and sinks into the gaps. Dark coats need the additive term.
        col += sheen * spine * max(0, strand - 0.35) * (sceneDay ? 0.42 : 0.24)
        col *= 0.78 + 0.34 * strand
        let part = groomed.part
        let under = alb * SIMD3<Float>(0.62, 0.56, 0.50)
        col = col * (1 - part * 0.55) + under * part * 0.35
        let lipD = (part - 0.42) / 0.16
        col += sheen * exp(-(lipD * lipD)) * 0.10
        let rim = 1 - CoatColor.smooth(-sample.sdf, 0.0, 0.045)
        col += sheen * rim * (sceneDay ? 0.12 : 0.08)
        if local.y > 0 { col *= 0.90 + 0.10 * CoatColor.smooth(0.18 - local.y, 0, 0.18) }
        col = SIMD3(1 - exp(-col.x * 1.12), 1 - exp(-col.y * 1.12), 1 - exp(-col.z * 1.12))
        let alpha = min(1, max(0, 1 - sample.sdf / fringe))
        return (col, alpha)
    }

    private static func drawFace(_ cg: CGContext, bounds: CGSize, pose: CatPose, catSize: Float, scene: RoomScene) {
        let shift: Float = pose.delightKind == 1 ? pose.delight * 0.035 : 0
        let smile: CGFloat = pose.delightKind == 0 ? 0 : CGFloat(pose.delight) * 4
        cg.setStrokeColor(UIColor(red: 0.18, green: 0.12, blue: 0.10, alpha: 0.85).cgColor)
        cg.setLineWidth(max(1.2, bounds.width * 0.004))
        cg.setLineCap(.round)
        for side: Float in [-0.04, 0.038] {
            let c = CatLayout.toView(SIMD2(-0.655 - shift, side), in: bounds, catSize: catSize)
            let s = CGFloat(CatLayout.scale(in: bounds, catSize: catSize)) * 0.032
            let center = CGPoint(x: c.x, y: c.y - smile * 0.15)
            cg.addArc(center: center, radius: s, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: true)
            cg.strokePath()
        }
        let nose = CatLayout.toView(SIMD2(-0.71 - shift, 0.012), in: bounds, catSize: catSize)
        let nr = CGFloat(CatLayout.scale(in: bounds, catSize: catSize)) * 0.016
        cg.setFillColor(UIColor(red: 0.55, green: 0.34, blue: 0.32, alpha: 0.9).cgColor)
        cg.move(to: CGPoint(x: nose.x - nr, y: nose.y - nr * 0.2))
        cg.addLine(to: CGPoint(x: nose.x + nr, y: nose.y - nr * 0.2))
        cg.addLine(to: CGPoint(x: nose.x, y: nose.y + nr))
        cg.closePath()
        cg.fillPath()
        cg.setStrokeColor(UIColor(white: 0.1, alpha: scene == .day ? 0.28 : 0.4).cgColor)
        cg.setLineWidth(0.8)
        for side: Float in [-1, 1] {
            let origin = CatLayout.toView(SIMD2(-0.66 - shift, 0.012 + side * 0.03), in: bounds, catSize: catSize)
            let len = CGFloat(CatLayout.scale(in: bounds, catSize: catSize)) * 0.18
            for angle in [-0.5, -0.15, 0.2] as [CGFloat] {
                let a = angle * CGFloat(side)
                cg.move(to: origin)
                cg.addLine(to: CGPoint(x: origin.x - cos(a) * len, y: origin.y + sin(a) * len * CGFloat(side)))
                cg.strokePath()
            }
        }
    }

    private static func drawRain(_ cg: CGContext, bounds: CGSize, time: Float, night: Bool) {
        let window = CatLayout.windowRect(in: bounds)
        cg.saveGState()
        cg.addPath(UIBezierPath(roundedRect: window, cornerRadius: 18).cgPath)
        cg.clip()
        cg.setStrokeColor(UIColor(white: night ? 0.85 : 0.55, alpha: 0.35).cgColor)
        cg.setLineWidth(1.2)
        cg.setLineCap(.round)
        for i in 0..<22 {
            let fi = Float(i)
            let x = window.minX + CGFloat((fi * 37).truncatingRemainder(dividingBy: Float(window.width)))
            let span = Float(window.height)
            let y = window.minY + CGFloat((time * 48 + fi * 19).truncatingRemainder(dividingBy: span))
            cg.move(to: CGPoint(x: x, y: y))
            cg.addLine(to: CGPoint(x: x + 1.5, y: y + 12))
        }
        cg.strokePath()
        cg.restoreGState()
    }
}
