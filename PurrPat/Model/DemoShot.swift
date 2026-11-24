import Foundation

enum DemoShot: String {
    case day, night, coats, paywall, stroke

    static var current: DemoShot? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-PurrPatShot"), index + 1 < args.count else { return nil }
        return DemoShot(rawValue: args[index + 1])
    }

    static var forceCPU: Bool {
        ProcessInfo.processInfo.arguments.contains("-PurrPatCPU")
    }

    /// The unit-test host launches the app. Skip the live render and audio so XCTest can attach.
    static var underTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var showsPaywall: Bool { self == .paywall }
    var animates: Bool { self == .stroke }
    var frozen: Bool { self != .stroke }
}
