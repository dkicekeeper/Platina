//
//  ScreenshotCaptureTests.swift
//  PlatinaUITests
//
//  The App Store's screenshots (scripts/capture_screenshots.sh): the app is launched once per
//  screen in its demo (`-ScreenshotDemo`: a made-up library in memory, art drawn on the device,
//  Plati from a script) and opens that screen itself (`-ScreenshotScreen`), so the test only waits
//  and keeps a full-resolution picture of it as an attachment, named "NN-screen".
//
//  Environment (TEST_RUNNER_ prefix on xcodebuild):
//    SCREENSHOT_LANGUAGE   the app's language: "ru" or "en"
//    SCREENSHOT_LOCALE     its locale: "ru_RU", "en_US"
//    SCREENSHOT_SCREENS    the screens, comma-separated (default: all of them)
//

import XCTest

final class ScreenshotCaptureTests: XCTestCase {
    /// In the store's order: what Platina is first.
    private static let screens = ["path", "game", "plati", "chapter", "session", "walkthrough", "guide", "profile", "library"]

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testCaptureStoreScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        let language = environment["SCREENSHOT_LANGUAGE"] ?? "ru"
        let locale = environment["SCREENSHOT_LOCALE"] ?? "ru_RU"
        let only = environment["SCREENSHOT_SCREENS"].map { Set($0.split(separator: ",").map(String.init)) }

        for (index, screen) in Self.screens.enumerated() where only?.contains(screen) ?? true {
            let app = XCUIApplication()
            app.launchArguments = [
                "-ScreenshotDemo",
                "-ScreenshotScreen", screen,
                "-AppleLanguages", "(\(language))",
                "-AppleLocale", locale,
            ]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "\(screen): the app did not start")
            // The demo syncs its library and seeds the person's side in memory, then the screen
            // draws its art and settles its entrances.
            sleep(screen == "plati" || screen == "session" ? 10 : 8)

            let shot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = String(format: "%02d-%@", index + 1, screen)
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
