import Foundation

enum StrokeZone: Equatable {
    case outside, head, back, tail, other
}

/// Happiness, the purr that builds while you stroke, and the delight that follows.
struct CatMood: Equatable {
    private(set) var happiness: Double = 0.32
    private(set) var purrIntensity: Double = 0
    /// 0 none, 1 a slow stretch, 2 kneading.
    private(set) var delightKind: Int = 0
    /// 0...1 envelope of the current delight.
    private(set) var delight: Double = 0

    private var delightLeft: Double = 0
    private var delightTotal: Double = 1
    private var cooldown: Double = 0
    private var kneadNext = false

    mutating func noteStroke(speed: Double, alignment: Double, zone: StrokeZone, dt: Double) {
        let dt = max(0, dt)
        let gentle = speed >= 40 && speed <= 560 && alignment > 0.2
        let rough = speed > 880
        let against = alignment < -0.2
        if gentle && (zone == .head || zone == .back) {
            happiness = min(1, happiness + dt * 0.16)
            purrIntensity = min(1, purrIntensity + dt * 0.45)
        } else if gentle && zone == .tail {
            happiness = min(1, happiness + dt * 0.06)
            purrIntensity = min(1, purrIntensity + dt * 0.20)
        } else if rough || against {
            happiness = max(0, happiness - dt * 0.30)
            purrIntensity = max(0, purrIntensity - dt * 1.10)
        } else if speed > 20 {
            purrIntensity = min(1, purrIntensity + dt * 0.08)
        }
        if happiness > 0.86 && delightKind == 0 && cooldown <= 0 {
            delightKind = kneadNext ? 2 : 1
            kneadNext.toggle()
            delightTotal = delightKind == 2 ? 2.6 : 3.4
            delightLeft = delightTotal
            delight = 0
        }
    }

    mutating func idle(dt: Double) {
        let dt = max(0, dt)
        happiness += (0.32 - happiness) * (1 - exp(-dt * 0.05))
        purrIntensity = max(0, purrIntensity - dt * 0.40)
        if cooldown > 0 { cooldown = max(0, cooldown - dt) }
        guard delightLeft > 0 else {
            delight = 0
            return
        }
        delightLeft -= dt
        let u = min(1, max(0, 1 - delightLeft / delightTotal))
        delight = sin(u * .pi)
        if delightLeft <= 0 {
            delight = 0
            delightKind = 0
            delightLeft = 0
            cooldown = 8
        }
    }
}
