import XCTest

final class EnhancementFlowTests: XCTestCase {
    @MainActor func testSavedSessionCanBeExcludedAndCountedAgainAndWeeklyReportOpens() {
        continueAfterFailure = false
        let app = launchApp()
        app.buttons["workout.start"].tap()
        let finish = app.buttons["workout.finish"]
        reveal(finish, in: app); finish.tap(); app.alerts.buttons["إنهاء وحفظ"].tap()
        let edit = app.buttons["workout.summary.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10)); reveal(edit, in: app); edit.tap()
        let title = app.textFields["session.edit.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let excluded = app.switches["session.edit.excluded"]
        reveal(excluded, in: app)
        excluded.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertEqual(excluded.value as? String, "1")
        capture(app, name: "Arabic saved session editor exclusion")
        app.buttons["session.edit.save"].tap()
        XCTAssertTrue(app.staticTexts["جلسة تجريبية محفوظة"].waitForExistence(timeout: 5))
        app.buttons["workout.summary.done"].tap()
        app.tabBars.buttons["تقدّمي"].tap()
        let completed = app.descendants(matching: .any).matching(identifier: "progress.completed").firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertTrue(completed.label.contains("٠") || completed.label.contains("0"))
        let weekly = app.buttons["progress.weeklyReport"]
        reveal(weekly, in: app); weekly.tap()
        XCTAssertTrue(app.navigationBars["تقريرك الأسبوعي"].waitForExistence(timeout: 5))
        capture(app, name: "Arabic weekly report on device")
        app.tabBars.buttons["التمرين"].tap()
        let history = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.history.")).firstMatch
        reveal(history, in: app); history.tap()
        reveal(edit, in: app); edit.tap()
        reveal(excluded, in: app)
        excluded.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertEqual(excluded.value as? String, "0")
        app.buttons["session.edit.save"].tap()
        XCTAssertTrue(app.staticTexts["أحسنت، تمرينك محفوظ"].waitForExistence(timeout: 5))
        app.buttons["workout.summary.done"].tap()
        app.tabBars.buttons["تقدّمي"].tap()
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertTrue(completed.label.contains("١") || completed.label.contains("1"))
    }

    @MainActor func testTimedExerciseLogsSecondsAndShowsNativeStartEndPreview() {
        continueAfterFailure = false
        let app = launchApp()
        app.buttons["workout.start"].tap()
        let add = app.buttons["workout.addExercise"]
        reveal(add, in: app); add.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("الثبات الأمامي")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "الثبات الأمامي")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let seconds = app.textFields["set.seconds.0"]
        reveal(seconds, in: app); seconds.tap(); seconds.typeText("30")
        app.buttons["إخفاء لوحة المفاتيح"].tap()
        let complete = app.buttons["set.complete.0"]
        reveal(complete, in: app); complete.tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 4) {
            ["السماح", "Allow", "حسنًا", "OK"].map { permission.buttons[$0] }.first { $0.exists }?.tap()
        }
        if app.alerts.buttons["حسنًا"].exists { app.alerts.buttons["حسنًا"].tap() }
        XCTAssertTrue(complete.label.contains("إلغاء إنجاز الجولة"))
        capture(app, name: "Arabic timed plank logging")
        let guide = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.exercise.guide.")).firstMatch
        reveal(guide, in: app); guide.tap()
        let play = app.buttons["guide.motion.play"]
        reveal(play, in: app)
        capture(app, name: "Arabic anatomical pose playback")
        XCTAssertTrue(app.segmentedControls["guide.motion.phase"].exists)
        if play.isEnabled { play.tap(); play.tap() }
        app.buttons["exercise.guide.done"].tap()
        let finish = app.buttons["workout.finish"]
        reveal(finish, in: app); finish.tap(); app.alerts.buttons["إنهاء وحفظ"].tap()
        XCTAssertTrue(app.buttons["workout.summary.done"].waitForExistence(timeout: 10))
        capture(app, name: "Arabic saved timed set summary")
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
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 where !element.exists || !element.isHittable {
            let up = element.exists && element.frame.height > 0 ? element.frame.midY > app.frame.midY : true
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.70 : 0.40)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.40 : 0.70)), withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable)
    }
    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(data: app.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + " accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
