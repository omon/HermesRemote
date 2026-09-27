import XCTest

final class KeyboardBehaviorTests: XCTestCase {
    func testSettingsKeyboardAppearsAndDismisses() {
        let app = XCUIApplication()
        app.launch()

        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        // Terminal must not retain first responder when Settings is selected.
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        let username = app.textFields["settings.username"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let done = app.buttons["完了"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
    }

}

private extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)],
                              timeout: timeout) == .completed
    }
}
