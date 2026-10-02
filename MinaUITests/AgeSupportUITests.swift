import XCTest

final class AgeSupportUITests: XCTestCase {
    func testOlderGuideAndCareChecklistAtAccessibilityTextSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-seed-days", "20", "-tab", "guide", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let picker = app.scrollViews["guide-stage-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        let stage = app.buttons["guide-stage-months-30-35"]
        for _ in 0..<12 {
            if stage.exists && stage.isHittable { break }
            picker.swipeLeft()
        }
        XCTAssertTrue(stage.isHittable)
        stage.tap()
        XCTAssertTrue(app.staticTexts["Meals, naps, words and play: a shared record through toddlerhood."].waitForExistence(timeout: 3))
        XCTAssertTrue(stage.isSelected)
        let visits = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Visits & vaccines")).firstMatch
        for _ in 0..<6 {
            if visits.exists && visits.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(visits.isHittable)
        visits.tap()
        let checkup = app.buttons["30-month checkup"]
        for _ in 0..<15 {
            if checkup.exists && checkup.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(checkup.isHittable)
        XCTAssertGreaterThanOrEqual(checkup.frame.height, 44)
        XCTAssertTrue((checkup.value as? String)?.contains("Growth and developmental screening") == true)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Toddler care checklist at accessibility XXXL"
        image.lifetime = .keepAlways
        add(image)
    }
}
