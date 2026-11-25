import Foundation

enum Entitlement {
    static func coatUnlocked(_ coat: Coat, isPro: Bool) -> Bool {
        coat.isFree || isPro
    }

    static func sceneUnlocked(_ scene: RoomScene, isPro: Bool) -> Bool {
        scene == .day || isPro
    }

    static func rainUnlocked(isPro: Bool) -> Bool { isPro }

    static func handStyleUnlocked(_ style: HandStyle, isPro: Bool) -> Bool {
        style.isFree || isPro
    }
}
