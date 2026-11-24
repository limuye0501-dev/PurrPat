import Foundation

/// Original coats. The first four are free; the rest are part of Pro.
enum Coat: Int, CaseIterable, Identifiable, Codable {
    case midnight
    case ember
    case patchwork
    case cloud
    case mackerel
    case tuxedo
    case tortie
    case slate
    case brindle
    case sealPoint
    case bluePoint
    case silverFox
    case forest

    var id: Int { rawValue }
    var isFree: Bool { rawValue < 4 }

    /// Longer coats get a slightly softer fringe in the shader.
    var furLength: Float {
        switch self {
        case .silverFox, .forest, .bluePoint: return 1.35
        case .cloud, .patchwork: return 1.1
        default: return 1
        }
    }

    var title: String {
        switch self {
        case .midnight: return String(localized: "Midnight")
        case .ember: return String(localized: "Ember")
        case .patchwork: return String(localized: "Patchwork")
        case .cloud: return String(localized: "Cloud")
        case .mackerel: return String(localized: "Mackerel")
        case .tuxedo: return String(localized: "Tuxedo")
        case .tortie: return String(localized: "Tortie")
        case .slate: return String(localized: "Slate")
        case .brindle: return String(localized: "Brindle")
        case .sealPoint: return String(localized: "Seal Point")
        case .bluePoint: return String(localized: "Blue Point")
        case .silverFox: return String(localized: "Silver Fox")
        case .forest: return String(localized: "Forest")
        }
    }

    /// Flat color for the picker chip. Patterns live in the renderer.
    var swatch: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .midnight: return (0.16, 0.15, 0.17)
        case .ember: return (0.86, 0.48, 0.18)
        case .patchwork: return (0.93, 0.78, 0.55)
        case .cloud: return (0.93, 0.91, 0.88)
        case .mackerel: return (0.62, 0.52, 0.40)
        case .tuxedo: return (0.12, 0.12, 0.13)
        case .tortie: return (0.45, 0.24, 0.14)
        case .slate: return (0.50, 0.53, 0.58)
        case .brindle: return (0.55, 0.36, 0.20)
        case .sealPoint: return (0.86, 0.78, 0.66)
        case .bluePoint: return (0.78, 0.82, 0.88)
        case .silverFox: return (0.72, 0.72, 0.70)
        case .forest: return (0.42, 0.36, 0.28)
        }
    }
}

enum HandStyle: String, CaseIterable, Identifiable, Codable {
    case mist, cream, navy, ink

    var id: String { rawValue }
    var isFree: Bool { self == .mist }

    var assetName: String {
        switch self {
        case .mist: return "HandMist"
        case .cream: return "HandCream"
        case .navy: return "HandNavy"
        case .ink: return "HandInk"
        }
    }

    var title: String {
        switch self {
        case .mist: return String(localized: "Mist")
        case .cream: return String(localized: "Cream")
        case .navy: return String(localized: "Navy")
        case .ink: return String(localized: "Ink")
        }
    }

    /// Finger-pad point in the overlay image, unit coordinates.
    static let anchor = CGPoint(x: 0.82, y: 0.08)
    static let aspect: CGFloat = 676.0 / 850.0
}

enum RoomScene: Int, Codable {
    case day
    case night

    var title: String {
        self == .day ? String(localized: "Daylight") : String(localized: "Moonlight")
    }
}
