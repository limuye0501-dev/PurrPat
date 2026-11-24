import Foundation

struct TailState: Equatable {
    private(set) var stretch: Double = 0
    private var velocity: Double = 0
    private(set) var dragging = false

    mutating func beginGrab() {
        dragging = true
        velocity = 0
    }

    /// `outward` is 0 at the base and 1 fully extended.
    mutating func drag(outward: Double) {
        dragging = true
        velocity = 0
        stretch = min(1, max(0, outward))
    }

    mutating func endGrab() {
        dragging = false
    }

    mutating func tick(dt: Double) {
        let dt = min(max(dt, 0), 1.0 / 20)
        guard !dragging else { return }
        let k = 8.0
        let c = 4.5
        let acc = -k * stretch - c * velocity
        velocity += acc * dt
        stretch = max(0, stretch + velocity * dt)
        if stretch < 0.001 && abs(velocity) < 0.01 {
            stretch = 0
            velocity = 0
        }
    }
}
