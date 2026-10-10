import AppIntents
import XCTest

final class MainFlowTests: XCTestCase {
    @MainActor
    func testCreatePlanLogWorkoutAndViewProgress() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launchEnvironment["FITNESS_TESTING"] = "1"
        addUIInterruptionMonitor(withDescription: "Local notification permission") { alert in
            for label in ["السماح", "Allow", "حسنًا", "OK"] where alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            return false
        }
        app.launch()
        let plansTab = app.tabBars.buttons["خططي"]
        XCTAssertTrue(plansTab.waitForExistence(timeout: 15))
        plansTab.tap()
        let addPlan = app.buttons["plans.add"]
        XCTAssertTrue(addPlan.waitForExistence(timeout: 5))
        XCTAssertTrue(addPlan.isHittable)
        addPlan.tap()
        app.buttons["خطة جديدة"].tap()
        let template = app.buttons["planTemplate_ppl"]
        XCTAssertTrue(template.waitForExistence(timeout: 5)); template.tap()
        let name = app.textFields["plan.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        // Selecting all avoids keyboard-specific delete behavior in Arabic.
        name.press(forDuration: 1.2)
        if app.menuItems["تحديد الكل"].exists { app.menuItems["تحديد الكل"].tap() }
        name.typeText(" خطة الاختبار")
        app.buttons["plan.save"].tap()
        let start = app.buttons.matching(identifier: "startPlannedWorkoutButton").firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        let weight = app.textFields.matching(identifier: "set.weight.0").firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        weight.tap(); weight.typeText("20")
        let complete = app.buttons.matching(identifier: "set.complete.0").firstMatch
        XCTAssertTrue(complete.exists); complete.tap()
        // An interruption monitor is processed on the next application interaction.
        app.tap()
        if app.alerts.buttons["حسنًا"].exists { app.alerts.buttons["حسنًا"].tap() }
        let finish = app.buttons["workout.finish"]
        for _ in 0..<5 where !finish.isHittable { app.swipeUp() }
        XCTAssertTrue(finish.exists); finish.tap()
        let confirm = app.buttons["إنهاء وحفظ"]
        if confirm.waitForExistence(timeout: 2) { confirm.tap() }
        app.tabBars.buttons["تقدّمي"].tap()
        XCTAssertTrue(app.otherElements["progress.screen"].waitForExistence(timeout: 10) || app.navigationBars["تقدّمك"].exists)
        let completed = app.descendants(matching: .any).matching(identifier: "progress.completed").firstMatch
        XCTAssertTrue(completed.exists)
        XCTAssertTrue(completed.label.contains("١") || completed.label.contains("1"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Arabic workout progress"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
