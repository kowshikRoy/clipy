import XCTest

final class ClipyUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testLaunch() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Verify that the search field exists
        let searchField = app.textFields["Search..."]
        XCTAssertTrue(searchField.exists, "Search field should exist on launch")
    }

    func testClipboardMonitoring() throws {
        let app = XCUIApplication()
        app.launch()

        // Generate a unique string
        let uniqueString = "TestString_\(UUID().uuidString)"

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(uniqueString, forType: .string)

        // Wait for the app to pick it up
        // The app polls every 1 second.

        // Note: In some environments, accessing NSPasteboard from the test runner might not immediately reflect in the app under test
        // due to sandbox restrictions or focus issues. However, for a standard UI test target, this often works.
        // We look for static text that matches the unique string.

        let predicate = NSPredicate(format: "exists == true")
        let staticText = app.staticTexts[uniqueString]

        // Increase timeout to allow for polling interval (1s) + processing
        expectation(for: predicate, evaluatedWith: staticText, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)

        XCTAssertTrue(staticText.exists)
    }

    func testSearch() throws {
        let app = XCUIApplication()
        app.launch()

        let uniqueString = "SearchTarget_\(UUID().uuidString)"

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(uniqueString, forType: .string)

        // Wait for it to appear
        let targetText = app.staticTexts[uniqueString]
        XCTAssertTrue(targetText.waitForExistence(timeout: 5))

        // Find search field
        let searchField = app.textFields["Search..."]
        XCTAssertTrue(searchField.exists)

        searchField.click()
        searchField.typeText(uniqueString)

        // Verify it's still visible (filtered)
        XCTAssertTrue(targetText.exists)

        // Search for something else to filter it out
        // Clear text by double clicking and deleting
        searchField.doubleClick()
        searchField.typeText(XCUIKeyboardKey.delete.rawValue)

        searchField.typeText("NonExistentString_" + UUID().uuidString)

        XCTAssertFalse(targetText.exists)
    }
}
