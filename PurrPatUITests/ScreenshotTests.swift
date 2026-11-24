import XCTest

final class ScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testShots() throws {
        let root = ProcessInfo.processInfo.environment["PURRPAT_SHOT_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? "/tmp/purrpat-shots"
        let directory = URL(fileURLWithPath: root, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for shot in ["day", "night", "coats", "paywall"] {
            let app = XCUIApplication()
            app.launchArguments = ["-PurrPatShot", shot, "-PurrPatCPU", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            if shot == "night" {
                app.launchArguments.append("-PurrPatUnlock")
            }
            app.launch()

            let ready = app.descendants(matching: .any)["shot-ready"]
            XCTAssertTrue(ready.waitForExistence(timeout: 45), "\(shot) did not render the cat")

            if shot == "paywall" {
                let button = app.buttons["unlock-pro"]
                XCTAssertTrue(button.waitForExistence(timeout: 15), "paywall button missing")
                let deadline = Date().addingTimeInterval(12)
                var label = button.label
                while Date() < deadline && !Self.hasPrice(label) {
                    Thread.sleep(forTimeInterval: 0.3)
                    label = button.label
                }
                try label.write(to: directory.appendingPathComponent("paywall-label.txt"), atomically: true, encoding: .utf8)
                XCTAssertTrue(Self.hasPrice(label), "Unlock button has no price: \(label)")
            }

            // Let the hand overlay commit after the still is marked ready.
            if shot == "day" {
                Thread.sleep(forTimeInterval: 0.8)
            }
            let data = XCUIScreen.main.screenshot().pngRepresentation
            try data.write(to: directory.appendingPathComponent("en-\(shot).png"))
            app.terminate()
        }
    }

    private static func hasPrice(_ label: String) -> Bool {
        label.contains("2.99") || label.contains("$") || label.contains("¥") || label.contains("￥")
    }
}
