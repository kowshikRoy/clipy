//
//  ClipyUITests.swift
//  ClipyUITests
//
//  Created by Clipy AI on 06.01.2026.
//

import XCTest

final class ClipyUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run.
        // The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLaunchAndSearch() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication(bundleIdentifier: "com.matrixcode.Clipy")
        app.launch()

        // Verify the app window is present
        let window = app.windows["Clipy"]
        XCTAssertTrue(window.exists, "The main Clipy window should exist")
        
        // Check for the search field
        let searchField = window.textFields["Search..."]
        XCTAssertTrue(searchField.exists, "Search field should exist")
        
        // Interact with search
        searchField.click()
        searchField.typeText("test query")
        
        // Clear search (optional, just to test interaction)
        searchField.typeText(XCUIKeyboardKey.delete.rawValue)
    }
    
    @MainActor
    func testListContent() throws {
        let app = XCUIApplication(bundleIdentifier: "com.matrixcode.Clipy")
        app.launch()
        
        let window = app.windows["Clipy"]
        print(app.debugDescription) // Debugging output
        
        // Depending on whether we have history or not, we might see "No clips found" or a list
        // We can check for either condition to ensure the UI is in a valid state
        
        let emptyState = window.staticTexts["No clips found"]
        let scrollView = window.scrollViews.firstMatch
        
        if emptyState.exists {
            XCTAssertTrue(emptyState.isHittable)
        } else {
            // If list exists, we expect a scroll view for the content
            XCTAssertTrue(scrollView.exists, "A ScrollView should exist when there are items")
        }
    }
}
