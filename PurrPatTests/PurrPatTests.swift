import simd
import XCTest
@testable import PurrPat

final class PurrPatTests: XCTestCase {
    func testGentleStrokeRaisesHappinessAndPurr() {
        var mood = CatMood()
        mood.noteStroke(speed: 180, alignment: 0.8, zone: .back, dt: 1)
        let mid = mood.purrIntensity
        mood.noteStroke(speed: 180, alignment: 0.8, zone: .head, dt: 1)
        XCTAssertGreaterThan(mood.happiness, 0.5)
        XCTAssertGreaterThan(mood.purrIntensity, mid)
    }

    func testLongGentleStrokeTriggersDelight() {
        var mood = CatMood()
        mood.noteStroke(speed: 200, alignment: 0.9, zone: .back, dt: 5)
        XCTAssertGreaterThan(mood.happiness, 0.86)
        XCTAssertNotEqual(mood.delightKind, 0)
    }

    func testRoughStrokeLowersHappiness() {
        var mood = CatMood()
        mood.noteStroke(speed: 1400, alignment: 0.9, zone: .back, dt: 1)
        XCTAssertLessThan(mood.happiness, 0.32)
    }

    func testAgainstTheGrainLowersHappiness() {
        var mood = CatMood()
        mood.noteStroke(speed: 200, alignment: -0.6, zone: .back, dt: 1)
        XCTAssertLessThan(mood.happiness, 0.32)
    }

    func testHappinessStaysInRange() {
        var mood = CatMood()
        mood.noteStroke(speed: 200, alignment: 1, zone: .head, dt: 40)
        XCTAssertLessThanOrEqual(mood.happiness, 1)
        mood.noteStroke(speed: 2000, alignment: -1, zone: .back, dt: 40)
        XCTAssertGreaterThanOrEqual(mood.happiness, 0)
    }

    func testGroomSpringsBack() {
        let groom = GroomField(width: 32, height: 24)
        groom.stamp(local: .zero, direction: SIMD2(1, 0), radius: 0.25, amount: 1)
        let before = groom.sample(local: .zero).part
        XCTAssertGreaterThan(before, 0.4)
        for _ in 0..<240 {
            groom.spring(dt: 1.0 / 60)
        }
        XCTAssertLessThan(groom.sample(local: .zero).part, before * 0.5)
    }

    func testTailStretchesAndRelaxes() {
        var tail = TailState()
        tail.beginGrab()
        tail.drag(outward: 0.85)
        XCTAssertGreaterThan(tail.stretch, 0.8)
        tail.endGrab()
        for _ in 0..<360 {
            tail.tick(dt: 1.0 / 60)
        }
        XCTAssertLessThan(tail.stretch, 0.15)
    }

    func testFreeCoatsAndProGates() {
        XCTAssertTrue(Entitlement.coatUnlocked(.black, isPro: false))
        XCTAssertTrue(Entitlement.coatUnlocked(.ginger, isPro: false))
        XCTAssertTrue(Entitlement.coatUnlocked(.white, isPro: false))
        XCTAssertTrue(Entitlement.coatUnlocked(.calico, isPro: false))
        XCTAssertFalse(Entitlement.coatUnlocked(.siamese, isPro: false))
        XCTAssertFalse(Entitlement.coatUnlocked(.silverTabby, isPro: false))
        XCTAssertTrue(Entitlement.coatUnlocked(.siamese, isPro: true))
        XCTAssertTrue(Entitlement.sceneUnlocked(.day, isPro: false))
        XCTAssertFalse(Entitlement.sceneUnlocked(.night, isPro: false))
        XCTAssertTrue(Entitlement.sceneUnlocked(.night, isPro: true))
        XCTAssertFalse(Entitlement.rainUnlocked(isPro: false))
        XCTAssertTrue(Entitlement.handStyleUnlocked(.mist, isPro: false))
        XCTAssertFalse(Entitlement.handStyleUnlocked(.navy, isPro: false))
        XCTAssertEqual(Coat.allCases.filter(\.isFree).count, 4)
        XCTAssertEqual(Coat.allCases.count, 11)
        XCTAssertEqual(Set(Coat.allCases.map(\.assetName)).count, 11)
    }

    func testAnatomyZonesAndGrain() {
        let pose = CatPose(chub: 0.35, breath: 0.4, earL: 0, earR: 0, tailStretch: 0, tailSway: 0, delight: 0, delightKind: 0)
        let head = CatAnatomy.sample(SIMD2(0.48, 0.27), pose: pose)
        XCTAssertEqual(head.zone, .head)
        XCTAssertLessThan(head.sdf, 0)
        let back = CatAnatomy.sample(SIMD2(0.48, 0.48), pose: pose)
        XCTAssertEqual(back.zone, .back)
        XCTAssertGreaterThan(back.grain.y, 0.5)
        let outside = CatAnatomy.sample(SIMD2(0.05, 0.05), pose: pose)
        XCTAssertEqual(outside.zone, .outside)
    }

    func testNightGradeCoolsAWarmColour() {
        let day = SIMD3<Float>(0.86, 0.78, 0.66)
        let night = simd_clamp(day * SIMD3<Float>(0.457, 0.643, 0.917) + SIMD3<Float>(-0.020, -0.018, 0.004), SIMD3(repeating: 0), SIMD3(repeating: 1))
        XCTAssertLessThan(night.x, day.x)
        XCTAssertGreaterThan(night.z, night.x)
    }

    func testPainterMakesAnImage() {
        let groom = GroomField(width: 24, height: 16)
        let pose = CatPose(chub: 0.3, breath: 0.5, earL: 0, earR: 0, tailStretch: 0.1, tailSway: 0, delight: 0, delightKind: 0)
        let image = ScenePainter.render(
            bounds: CGSize(width: 90, height: 160),
            scale: 1,
            coat: .ginger,
            scene: .day,
            pose: pose,
            groom: groom,
            rain: 0,
            time: 0.4,
            catSize: 1,
            interactive: true
        )
        XCTAssertEqual(image.size.width, 90, accuracy: 0.1)
        XCTAssertNotNil(image.cgImage)
    }
}
