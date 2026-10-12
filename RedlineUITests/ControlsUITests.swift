import XCTest

/// Drives the real window: sets small sizes through the pickers and the slider,
/// runs every test at once and stops them again.
final class ControlsUITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    @MainActor
    override func tearDown() async throws {
        app.terminate()
    }

    @MainActor
    func testRunAllAndStopAll() {
        let cpu = card("cpu"), gpu = card("gpu"), memory = card("memory"), disk = card("disk")
        let cards = [cpu, gpu, memory, disk]

        // Keep the load light enough for a CI runner.
        cpu.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0)
        XCTAssertTrue(cpu.staticTexts["1"].exists, "core slider did not update the core count")
        gpu.radioButtons["64"].click()
        memory.radioButtons["1"].click()
        disk.radioButtons["256"].click()
        XCTAssertTrue(memory.radioButtons["1"].isSelected, "memory picker did not take the selection")

        app.buttons["Run All Tests"].click()
        for card in cards {
            XCTAssertTrue(card.buttons["Stop"].waitForExistence(timeout: 10), "\(card.identifier) did not start")
        }
        XCTAssertFalse(memory.radioButtons["2"].isEnabled, "pickers stay editable while running")
        XCTAssertTrue(memory.staticTexts["1024 MB active"].waitForExistence(timeout: 30))

        app.buttons["Stop All"].click()
        for card in cards {
            XCTAssertTrue(card.buttons["Start"].waitForExistence(timeout: 10), "\(card.identifier) did not stop")
            XCTAssertTrue(card.staticTexts["Idle"].exists, "\(card.identifier) is not idle after Stop All")
        }
        XCTAssertTrue(app.buttons["Run All Tests"].exists)
    }

    @MainActor
    func testSingleCardStartAndStop() {
        let cpu = card("cpu")
        cpu.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0)
        cpu.radioButtons["Integer"].click()

        cpu.buttons["Start"].click()
        XCTAssertTrue(cpu.staticTexts["1 cores · Integer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Stop All"].exists, "bottom bar did not switch to Stop All")

        cpu.buttons["Stop"].click()
        XCTAssertTrue(cpu.staticTexts["Idle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Run All Tests"].exists)
    }

    @MainActor
    private func card(_ id: String) -> XCUIElement {
        let card = app.descendants(matching: .any)[id]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "card \(id) not found")
        return card
    }
}
