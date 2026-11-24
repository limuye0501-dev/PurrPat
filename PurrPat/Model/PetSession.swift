import CoreGraphics
import Foundation
import simd
import UIKit

@MainActor
final class PetSession: ObservableObject {
    let groom = GroomField()
    private(set) var mood = CatMood()
    private(set) var tail = TailState()
    private(set) var pose = CatPose()
    private(set) var time: Double = 0.55

    @Published var happiness: Double = 0.32
    @Published var purrLevel: Double = 0
    @Published var handAnchor: CGPoint?
    @Published var handAngle: CGFloat = -0.35
    @Published var handOpacity: Double = 0
    @Published var delightKind: Int = 0

    var onLevels: ((Double, Bool) -> Void)?

    private var touching = false
    private var grabbingTail = false
    private var lastLocal: SIMD2<Float>?
    private var lastPoint: CGPoint?
    private var lastTime: CFTimeInterval?
    private var scriptContact = false
    private var demo: DemoShot?
    private var demoHandLocal: SIMD2<Float>?
    private var reduceMotion = false

    func installDemo(settings: AppSettings, purchases: PurchaseManager) {
        guard let shot = DemoShot.current else { return }
        demo = shot
        switch shot {
        case .day:
            settings.scene = .day
            settings.coat = .black
            settings.handEnabled = true
            settings.chub = 0.32
            settings.catSize = 1
        case .night:
            settings.scene = .night
            settings.coat = .black
            settings.handEnabled = false
            settings.chub = 0.32
            settings.catSize = 1
        case .coats:
            settings.scene = .day
            settings.coat = .calico
            settings.handEnabled = false
            settings.chub = 0.32
        case .paywall:
            settings.scene = .day
            settings.coat = .ginger
            settings.handEnabled = false
        case .stroke:
            settings.scene = .day
            settings.coat = .ginger
            settings.handEnabled = true
            settings.chub = 0.32
            settings.purrEnabled = true
        }
        settings.clamp(isPro: purchases.isPro)
        if shot == .night { settings.scene = .night; settings.coat = .black }
        if shot == .day {
            stampPath()
            demoHandLocal = SIMD2(0.49, 0.56)
            time = 0.7
            handOpacity = 1
        }
        pose = makePose(settings: settings)
    }

    func placeDemoHand(in bounds: CGSize, settings: AppSettings) {
        guard touching == false, let local = demoHandLocal else { return }
        handAnchor = CatLayout.point(local, in: bounds, catSize: settings.catSize)
        handAngle = -0.4
        handOpacity = 1
    }

    var isFrozen: Bool { demo?.frozen == true }

    func tick(dt: Double, bounds: CGSize, settings: AppSettings) {
        reduceMotion = UIAccessibility.isReduceMotionEnabled
        let step = min(max(dt, 0), 0.05)
        if !isFrozen { time += step }
        let previousDelight = mood.delightKind
        pose = makePose(settings: settings)
        if demo == .stroke && !touching {
            driveScript(bounds: bounds, settings: settings, dt: step)
        } else if !touching {
            mood.idle(dt: step)
            tail.tick(dt: step)
            scriptContact = false
        } else {
            tail.tick(dt: step)
        }
        if !isFrozen { groom.spring(dt: Float(step)) }
        fadeHand(dt: step)
        pose = makePose(settings: settings)
        publish()
        onLevels?(mood.purrIntensity, settings.purrEnabled && (touching || scriptContact || mood.purrIntensity > 0.02))
        if previousDelight == 0 && mood.delightKind != 0 {
            onDelight?()
        }
    }

    var onDelight: (() -> Void)?

    init() {
        if let shot = DemoShot.current {
            demo = shot
            if shot == .day {
                stampPath()
                demoHandLocal = SIMD2(0.49, 0.56)
                time = 0.7
                handOpacity = 1
            }
        }
    }

    func pointer(at point: CGPoint, in bounds: CGSize, settings: AppSettings, when now: CFTimeInterval) {
        touching = true
        demoHandLocal = nil
        let local = CatLayout.uv(point, in: bounds, catSize: settings.catSize)
        if let prev = lastLocal, let last = lastTime {
            let dt = now - last
            if dt > 0.001 && dt < 0.25 {
                apply(from: prev, to: local, dt: dt, bounds: bounds, settings: settings)
                let dx = point.x - (lastPoint?.x ?? point.x)
                let dy = point.y - (lastPoint?.y ?? point.y)
                if abs(dx) + abs(dy) > 0.5 {
                    handAngle = max(-0.4, min(0.4, atan2(dy, dx) * 0.12))
                }
            }
        }
        lastLocal = local
        lastPoint = point
        lastTime = now
        handAnchor = point
        handOpacity = 1
        if !settings.hasStroked, let prev = lastLocal, simd_length(local - prev) > 0 {
            settings.hasStroked = true
        }
        publish()
    }

    func pointerEnded() {
        touching = false
        grabbingTail = false
        tail.endGrab()
        lastLocal = nil
        lastPoint = nil
        lastTime = nil
    }

    private func driveScript(bounds: CGSize, settings: AppSettings, dt: Double) {
        let period = 3.4
        let u = time.truncatingRemainder(dividingBy: period) / period
        let down = u < 0.7
        let t = Float(min(1, u / 0.7))
        let eased = t * t * (3 - 2 * t)
        let local = SIMD2<Float>(0.50, 0.32 + eased * 0.30)
        if down {
            scriptContact = true
            if let prev = lastLocal {
                apply(from: prev, to: local, dt: max(dt, 0.008), bounds: bounds, settings: settings)
            }
            lastLocal = local
            handAnchor = CatLayout.point(local, in: bounds, catSize: settings.catSize)
            handAngle = -0.45
            handOpacity = 1
        } else if scriptContact {
            scriptContact = false
            grabbingTail = false
            tail.endGrab()
            lastLocal = nil
            mood.idle(dt: dt)
        } else {
            mood.idle(dt: dt)
            tail.tick(dt: dt)
        }
    }

    private func apply(from prev: SIMD2<Float>, to local: SIMD2<Float>, dt: Double, bounds: CGSize, settings: AppSettings) {
        let delta = local - prev
        let span = CatLayout.pointsPerUV(in: bounds, catSize: settings.catSize)
        let speed = Double(hypot(delta.x * span.x, delta.y * span.y)) / dt
        let sample = CatAnatomy.sample(local, pose: pose)
        if sample.zone != .outside {
            groom.stamp(local: local, direction: delta, radius: 0.045, amount: 0.95)
            settings.hasStroked = true
        }
        let nearBase = simd_distance(prev, CatAnatomy.tailBase) < 0.08 || simd_distance(local, CatAnatomy.tailBase) < 0.07
        if !grabbingTail && nearBase && (sample.zone == .tail || sample.region == .tail) {
            grabbingTail = true
            tail.beginGrab()
        }
        if grabbingTail {
            let outward = (Double(simd_distance(local, CatAnatomy.tailBase)) - 0.04) / 0.28
            tail.drag(outward: outward)
        } else if sample.zone != .outside {
            let dir = simd_length(delta) > 1e-4 ? simd_normalize(delta) : SIMD2<Float>(1, 0)
            let align = Double(simd_dot(dir, sample.grain))
            mood.noteStroke(speed: speed, alignment: align, zone: sample.zone, dt: dt)
        }
    }

    private func stampPath() {
        let path: [SIMD2<Float>] = [
            SIMD2(0.50, 0.34), SIMD2(0.49, 0.44), SIMD2(0.49, 0.54), SIMD2(0.48, 0.62),
        ]
        for i in 0..<(path.count - 1) {
            let mid = (path[i] + path[i + 1]) * 0.5
            groom.stamp(local: path[i], direction: path[i + 1] - path[i], radius: 0.05, amount: 1)
            groom.stamp(local: mid, direction: path[i + 1] - path[i], radius: 0.05, amount: 1)
        }
    }

    private func makePose(settings: AppSettings) -> CatPose {
        var pose = CatPose()
        pose.chub = settings.chub
        pose.breath = reduceMotion ? 0.35 : breathValue(time)
        pose.earL = reduceMotion ? 0 : twitch(time, seed: 0.2)
        pose.earR = reduceMotion ? 0 : twitch(time + 1.7, seed: 1.4)
        pose.tailStretch = Float(tail.stretch)
        let swayAmp: Float = reduceMotion ? 0.01 : 0.035
        pose.tailSway = Float(sin(time * 0.7)) * swayAmp * Float(1 - tail.stretch)
        let delight = reduceMotion ? mood.delight * 0.35 : mood.delight
        pose.delight = Float(delight)
        pose.delightKind = mood.delightKind
        return pose
    }

    private func publish() {
        if abs(happiness - mood.happiness) > 0.008 { happiness = mood.happiness }
        if abs(purrLevel - mood.purrIntensity) > 0.02 { purrLevel = mood.purrIntensity }
        if delightKind != mood.delightKind { delightKind = mood.delightKind }
    }

    private func fadeHand(dt: Double) {
        if touching || scriptContact || demoHandLocal != nil {
            if handOpacity < 1 { handOpacity = 1 }
            return
        }
        guard handOpacity > 0 else { return }
        let next = max(0, handOpacity - dt / 0.4)
        handOpacity = next
        if next <= 0.02 {
            handOpacity = 0
            handAnchor = nil
        }
    }

    private func breathValue(_ time: Double) -> Float {
        let cycle = 2.7
        var p = time.truncatingRemainder(dividingBy: cycle) / cycle
        if p < 0 { p += 1 }
        let v: Double
        if p < 0.4 {
            v = sin(p / 0.4 * .pi)
        } else {
            v = sin((1 - (p - 0.4) / 0.6) * .pi)
        }
        return Float(v)
    }

    private func twitch(_ time: Double, seed: Double) -> Float {
        let period = 6.2 + seed
        let n = floor(time / period)
        let local = time - n * period
        let h = abs(sin(n * 12.9898 + seed * 78.233))
        let frac = h - floor(h)
        guard frac > 0.55, local < 0.18 else { return 0 }
        return Float(sin(local / 0.18 * .pi))
    }
}
