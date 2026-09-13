import XCTest

/// Drives the app through a parent's typical minute so a screen recording
/// shows it being used. Run while `xcrun simctl io <udid> recordVideo` is
/// capturing; every `beat` is a pause the edit can cut on.
final class TrailerTour: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-seed-days", "20", "-tab", "today"]
        app.launch()
    }

    private func beat(_ seconds: Double = 1.6) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    private func tap(_ element: XCUIElement, wait: Double = 4) {
        XCTAssertTrue(element.waitForExistence(timeout: wait), "missing \(element)")
        element.tap()
    }

    /// Buttons read their subtitle into the label ("Bottle, Last 3 oz"), so match the start.
    private func button(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix)).firstMatch
    }

    func testTour() throws {
        beat(2.5)

        // Bottle: quick pick 4, save.
        tap(button("Bottle")); beat(1.2)
        tap(app.buttons["4"].firstMatch.exists ? app.buttons["4"].firstMatch : button("4")); beat(0.8)
        tap(button("Save bottle")); beat(1.8)

        // Diaper: wet.
        tap(button("Diaper")); beat(0.9)
        tap(app.buttons["Wet"].firstMatch.exists ? app.buttons["Wet"].firstMatch : button("Wet")); beat(1.8)

        // Nursing timer: start on the suggested side, let it run, switch, stop.
        tap(button("Nurse")); beat(1.4)
        let left = button("Left"), right = button("Right")
        if left.waitForExistence(timeout: 3) { left.tap() } else { tap(right) }
        beat(2.4)
        if button("Switch side").exists { button("Switch side").tap(); beat(1.6) }
        tap(button("Done")); beat(1.8)

        // Scroll the timeline a little, then come back up.
        app.swipeUp(); beat(1.4); app.swipeDown(); beat(1.0)

        // Calendar: a day with dots, then History and a search.
        tap(app.tabBars.buttons["Calendar"]); beat(1.8)
        let day = app.staticTexts["5"].firstMatch
        if day.exists { day.tap(); beat(1.6) }
        tap(button("History")); beat(1.6)
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap(); beat(0.5)
            search.typeText("vitamin"); beat(1.8)
            let searchKey = app.keyboards.buttons["search"].firstMatch
            if searchKey.exists { searchKey.tap() } else { search.typeText("\n") }
            beat(1.2)
            let clear = search.buttons["Clear text"].firstMatch
            if clear.exists { clear.tap(); beat(0.4) }
            app.swipeUp(); beat(0.8)                                 // scroll dismisses the keyboard
        }
        tap(button("Feeds")); beat(1.4)
        tap(button("Sleep")); beat(1.4)
        app.swipeUp(); beat(1.2)
        app.navigationBars.buttons.firstMatch.tap(); beat(1.0)       // back to Calendar

        // Trends, then Guide with a milestone tapped.
        tap(app.tabBars.buttons["Trends"]); beat(2.2)
        app.swipeUp(); beat(1.6)
        tap(app.tabBars.buttons["Guide"]); beat(1.8)
        app.swipeUp(); beat(1.0); app.swipeUp(); beat(1.0)
        let milestone = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'smile' OR label CONTAINS[c] 'head'")).firstMatch
        if milestone.exists { milestone.tap(); beat(1.6) }

        // Back to Today, open Ask for the closing shot.
        tap(app.tabBars.buttons["Today"]); beat(1.4)
        tap(button("Ask")); beat(2.4)
        tap(button("Done")); beat(1.5)
    }
}
