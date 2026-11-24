import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var coat: Coat { didSet { save("coat", coat.rawValue) } }
    @Published var catSize: Float { didSet { save("size", catSize) } }
    @Published var chub: Float { didSet { save("chub", chub) } }
    @Published var scene: RoomScene { didSet { save("scene", scene.rawValue) } }
    @Published var rain: Bool { didSet { save("rain", rain) } }
    @Published var handEnabled: Bool { didSet { save("hand", handEnabled) } }
    @Published var handStyle: HandStyle { didSet { save("sleeve", handStyle.rawValue) } }
    @Published var purrEnabled: Bool { didSet { save("purr", purrEnabled) } }
    @Published var hasStroked: Bool { didSet { save("stroked", hasStroked) } }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        coat = Coat(rawValue: d.object(forKey: "purrpat.coat") as? Int ?? 0) ?? .black
        catSize = d.object(forKey: "purrpat.size") as? Float ?? 1
        chub = d.object(forKey: "purrpat.chub") as? Float ?? 0.32
        scene = RoomScene(rawValue: d.object(forKey: "purrpat.scene") as? Int ?? 0) ?? .day
        rain = d.bool(forKey: "purrpat.rain")
        handEnabled = d.object(forKey: "purrpat.hand") as? Bool ?? true
        handStyle = HandStyle(rawValue: d.string(forKey: "purrpat.sleeve") ?? "") ?? .mist
        purrEnabled = d.object(forKey: "purrpat.purr") as? Bool ?? true
        hasStroked = d.bool(forKey: "purrpat.stroked")
        catSize = min(1.2, max(0.85, catSize))
        chub = min(1, max(0, chub))
    }

    func clamp(isPro: Bool) {
        if !Entitlement.coatUnlocked(coat, isPro: isPro) { coat = .black }
        if !Entitlement.sceneUnlocked(scene, isPro: isPro) { scene = .day }
        if !Entitlement.rainUnlocked(isPro: isPro) { rain = false }
        if !Entitlement.handStyleUnlocked(handStyle, isPro: isPro) { handStyle = .mist }
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: "purrpat." + key)
    }
}
