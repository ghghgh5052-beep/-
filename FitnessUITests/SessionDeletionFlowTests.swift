import XCTest

final class SessionDeletionFlowTests: XCTestCase {
    @MainActor func testDiscardLoggedPausedSessionDoesNotCreateHistory() {
        continueAfterFailure = false
        let app = launchApp()
        app.buttons["workout.start"].tap()
        let add = app.buttons["workout.addExercise"]
        reveal(add, in: app); add.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        if !search.isHittable { app.swipeDown() }
        search.tap(); search.typeText("ضغط الصدر بالبار")
        let pick = app.buttons["exercise.picker.00000001-0000-4000-8000-000000000001"]
        XCTAssertTrue(pick.waitForExistence(timeout: 5)); pick.tap()
        let weight = app.textFields.matching(identifier: "set.weight.0").firstMatch
        reveal(weight, in: app); weight.tap(); weight.typeText("20")
        let hide = app.buttons["إخفاء لوحة المفاتيح"]
        if hide.isHittable { hide.tap() }
        let complete = app.buttons.matching(identifier: "set.complete.0").firstMatch
        reveal(complete, in: app); complete.tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 5) {
            let allow = ["السماح", "Allow", "حسنًا", "OK"].map { permission.buttons[$0] }.first { $0.exists }
            XCTAssertNotNil(allow); allow?.tap()
        }
        if app.alerts.buttons["حسنًا"].exists { app.alerts.buttons["حسنًا"].tap() }
        XCTAssertTrue(complete.label.contains("إلغاء إنجاز الجولة"))
        let pause = app.buttons["workout.pause"]
        reveal(pause, in: app, up: false); pause.tap()
        let discard = app.buttons["workout.discard"]
        reveal(discard, in: app); discard.tap()
        capture(app, name: "Arabic discard logged paused session confirmation")
        app.alerts.buttons["متابعة التمرين"].tap()
        XCTAssertTrue(app.navigationBars["جلسة التمرين"].exists)
        discard.tap(); app.alerts.buttons["workout.discard.confirm"].tap()
        XCTAssertTrue(app.staticTexts["تاريخك يبدأ من هنا"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["workout.summary.done"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.history.")).firstMatch.exists)
        app.tabBars.buttons["تقدّمي"].tap()
        let count = app.descendants(matching: .any).matching(identifier: "progress.completed").firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.label.contains("٠") || count.label.contains("0"))
        capture(app, name: "Arabic zero history after discarded logged session")
    }

    @MainActor func testRTLHistorySwipeRequiresConfirmationBeforeDeleting() {
        continueAfterFailure = false
        let app = launchApp()
        app.buttons["workout.start"].tap()
        let finish = app.buttons["workout.finish"]
        reveal(finish, in: app); finish.tap()
        app.alerts.buttons["إنهاء وحفظ"].tap()
        let done = app.buttons["workout.summary.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10)); done.tap()
        let history = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.history.")).firstMatch
        reveal(history, in: app)
        // SwiftUI trailing actions are revealed with a rightward swipe in RTL.
        history.swipeRight()
        let remove = app.buttons["حذف جلسة تمرين حر"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        capture(app, name: "Arabic RTL history swipe deletion confirmation")
        app.alerts.buttons["تراجع"].tap()
        XCTAssertTrue(history.exists)
        history.tap()
        let delete = app.buttons["workout.summary.delete"]
        reveal(delete, in: app); delete.tap()
        app.alerts.buttons["workout.delete.confirm"].tap()
        XCTAssertTrue(app.staticTexts["تاريخك يبدأ من هنا"].waitForExistence(timeout: 10))
        XCTAssertFalse(history.exists)
        capture(app, name: "Arabic empty history after session deletion")
    }

    @MainActor private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launchEnvironment["FITNESS_TESTING"] = "1"
        app.launchEnvironment["FITNESS_TEST_THEME"] = ProcessInfo.processInfo.environment["UI_TEST_THEME"] ?? "system"
        app.launchEnvironment["FITNESS_TEST_DIGITS"] = ProcessInfo.processInfo.environment["UI_TEST_DIGITS"] ?? "arabic"
        app.launch()
        XCTAssertTrue(app.buttons["workout.start"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<12 where !element.exists || !element.isHittable {
            let direction = element.exists && element.frame.height > 0 ? element.frame.midY > app.frame.midY : up
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: direction ? 0.70 : 0.40))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: direction ? 0.40 : 0.70))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        if !element.exists || !element.isHittable { capture(app, name: "Unreachable " + element.identifier) }
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable)
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(data: app.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
