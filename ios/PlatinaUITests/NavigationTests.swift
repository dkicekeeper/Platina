//
//  NavigationTests.swift
//  PlatinaUITests
//
//  The ways into a game's screen, in the demo (`-ScreenshotDemo`: a made-up library in memory,
//  nothing reaches PSN): from the Path and from the library. A screen that hangs the app fails
//  here instead of on the owner's phone (2026-11-26: a game opened from the Path froze the app).
//  CI runs them after the package tests (.github/workflows/ios.yml).
//

import XCTest

final class NavigationTests: XCTestCase {
    /// A game the demo puts among the games the person goes for, so the Path shows it.
    private static let game = "Neon Rally Zero"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPathOpensGameAndComesBack() throws {
        let app = launchDemo()
        let card = app.staticTexts[Self.game].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 60), "The Path did not show \(Self.game)")
        scrollUntilHittable(card, in: app)
        card.tap()

        XCTAssertTrue(gameScreen(in: app).waitForExistence(timeout: 20), "The game did not open from the Path")
        // A hung app answers nothing: going back proves it still runs.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Back from the game, the Path did not come back")
    }

    @MainActor
    func testLibraryOpensGame() throws {
        let app = launchDemo()
        let tab = app.tabBars.buttons["Игры"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 60), "No Games tab")
        tab.tap()
        let row = app.staticTexts[Self.game].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "The library did not show \(Self.game)")
        scrollUntilHittable(row, in: app)
        row.tap()
        XCTAssertTrue(gameScreen(in: app).waitForExistence(timeout: 20), "The game did not open from the library")
    }

    // MARK: Helpers

    /// The demo in Russian, on the Path, its library synced.
    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ScreenshotDemo", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "The app did not start")
        return app
    }

    /// The game's screen (`GameView` marks its scroll view).
    private func gameScreen(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "game-screen").firstMatch
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable {
            app.swipeUp()
        }
    }
}
