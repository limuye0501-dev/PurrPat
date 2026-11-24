import Foundation

/// Photographic coats. The first four are free; the rest are part of Pro.
enum Coat: Int, CaseIterable, Identifiable, Codable {
    case black
    case ginger
    case white
    case calico
    case silverTabby
    case tuxedo
    case blueGrey
    case ragdoll
    case tortie
    case brownTabby
    case siamese

    var id: Int { rawValue }
    var isFree: Bool { rawValue < 4 }

    /// Bundle name for `plate-*.jpg`, `mask-*.png`, and `swatch-*.png`.
    var assetName: String {
        switch self {
        case .black: return "black"
        case .ginger: return "ginger"
        case .white: return "white"
        case .calico: return "calico"
        case .silverTabby: return "silvertabby"
        case .tuxedo: return "tuxedo"
        case .blueGrey: return "bluegrey"
        case .ragdoll: return "ragdoll"
        case .tortie: return "tortie"
        case .brownTabby: return "browntabby"
        case .siamese: return "siamese"
        }
    }

    var title: String {
        switch self {
        case .black: return String(localized: "Black")
        case .ginger: return String(localized: "Ginger")
        case .white: return String(localized: "White")
        case .calico: return String(localized: "Calico")
        case .silverTabby: return String(localized: "Silver Tabby")
        case .tuxedo: return String(localized: "Tuxedo")
        case .blueGrey: return String(localized: "Blue-grey")
        case .ragdoll: return String(localized: "Ragdoll")
        case .tortie: return String(localized: "Tortie")
        case .brownTabby: return String(localized: "Brown Tabby")
        case .siamese: return String(localized: "Siamese")
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

    /// Middle fingertip in the overlay image, unit coordinates. The wrist sits down-left of this point.
    static let anchor = CGPoint(x: 0.86, y: 0.02)
    static let aspect: CGFloat = 676.0 / 850.0
}

enum RoomScene: Int, Codable {
    case day
    case night

    var title: String {
        self == .day ? String(localized: "Daylight") : String(localized: "Moonlight")
    }
}
