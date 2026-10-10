import XCTest

final class SmartFlowTests: XCTestCase {
    private let pushUpID = "00000001-0000-4000-8000-000000000008"

    @MainActor
    func testPreviewEditsStartAdviceLogAndRecoveryUseActualSavedData() {
        continueAfterFailure = false
        let app = launchApp()
        openGenerator(app)
        let generate = app.buttons["smart.generate"]
        reveal(generate, in: app)
        generate.tap()
        let previewTitle = app.staticTexts["smart.preview.title"]
        reveal(previewTitle, in: app)
        XCTAssertTrue(previewTitle.label.contains("بناء العضلات"))
        capture(app, name: "Arabic generated bodyweight preview")
        let edit = app.buttons["smart.edit.\(pushUpID)"]
        reveal(edit, in: app)
        edit.tap()
        let repetitions = app.textFields["smart.editor.reps"]
        XCTAssertTrue(repetitions.waitForExistence(timeout: 5))
        repetitions.tap(); repetitions.typeText("12")
        let suggestedWeight = app.textFields["smart.editor.weight"]
        suggestedWeight.tap(); suggestedWeight.typeText("10")
        app.buttons["smart.editor.save"].tap()
        let start = app.buttons["smart.start"]
        reveal(start, in: app)
        XCTAssertTrue(start.isEnabled)
        capture(app, name: "Arabic reviewed editable workout preview")
        start.tap()
        let weight = app.textFields.matching(identifier: "set.weight.0").firstMatch
        reveal(weight, in: app)
        XCTAssertTrue(["10", "١٠"].contains(weight.value as? String ?? ""))
        let reps = app.textFields.matching(identifier: "set.reps.0").firstMatch
        XCTAssertTrue(["12", "١٢"].contains(reps.value as? String ?? ""))
        capture(app, name: "Arabic generated prescription persisted in workout")
        let options = app.buttons["workout.exercise.options.\(pushUpID)"]
        reveal(options, in: app, up: false)
        options.tap()
        app.buttons["اقتراح الأوزان والتكرارات"].tap()
        let reason = app.staticTexts["advice.reason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertTrue(reason.label.contains("لا يوجد وزن إضافي مقترح"))
        capture(app, name: "Arabic honest weight advice without prior history")
        let adviceWeight = app.textFields["advice.weight"]
        adviceWeight.tap(); adviceWeight.typeText("5")
        let apply = app.buttons["advice.apply"]
        reveal(apply, in: app)
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        reveal(weight, in: app)
        XCTAssertTrue(["5", "٥"].contains(weight.value as? String ?? ""))
        XCTAssertTrue(["10", "١٠"].contains(reps.value as? String ?? ""))
        let complete = app.buttons.matching(identifier: "set.complete.0").firstMatch
        complete.tap()
        allowNotificationIfShown()
        XCTAssertTrue(complete.label.contains("إلغاء إنجاز الجولة"))
        let finish = app.buttons["workout.finish"]
        reveal(finish, in: app)
        finish.tap()
        let confirm = app.buttons["إنهاء وحفظ"]
        if confirm.waitForExistence(timeout: 2) { confirm.tap() }
        let done = app.buttons["workout.summary.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        let volume = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "٥٠ كجم", "50 كجم")).firstMatch
        XCTAssertTrue(volume.exists, "Only the completed set contributes 5 kg × 10 reps")
        done.tap()
        app.tabBars.buttons["تقدّمي"].tap()
        let recovery = app.buttons["progress.recovery"]
        reveal(recovery, in: app)
        recovery.tap()
        XCTAssertTrue(app.navigationBars["استشفاء العضلات"].waitForExistence(timeout: 5))
        capture(app, name: "Arabic front and back muscle map after saved workout")
        let readiness = app.staticTexts["recovery.detail.readiness"]
        reveal(readiness, in: app)
        XCTAssertTrue(readiness.label.contains("٩٠") || readiness.label.contains("90"))
        let sets = app.descendants(matching: .any).matching(identifier: "recovery.detail.sets").firstMatch
        XCTAssertTrue(sets.label.contains("١") || sets.label.contains("1"))
        capture(app, name: "Arabic front and back recovery from completed workout")
        let calves = app.buttons["recovery.region.calves"]
        reveal(calves, in: app)
        XCTAssertTrue(calves.label.contains("غير محدد"))
        calves.tap()
        reveal(readiness, in: app, up: false)
        XCTAssertTrue(readiness.label.contains("غير محدد"))
        capture(app, name: "Arabic recovery distinguishes trained and unknown muscles")
    }

    @MainActor
    func testCancelledPreviewCreatesNoWorkoutAndRetainsExactEquipmentPreferences() {
        continueAfterFailure = false
        let app = launchApp()
        openGenerator(app)
        let equipment = app.buttons["smart.equipment"]
        reveal(equipment, in: app)
        equipment.tap()
        let dumbbells = app.buttons["smart.equipment.dumbbell"]
        reveal(dumbbells, in: app)
        dumbbells.tap()
        let bench = app.buttons["smart.equipment.bench"]
        reveal(bench, in: app)
        bench.tap()
        app.buttons["تم"].tap()
        let generate = app.buttons["smart.generate"]
        reveal(generate, in: app)
        generate.tap()
        let preview = app.staticTexts["smart.preview.title"]
        reveal(preview, in: app)
        capture(app, name: "Arabic equipment selected and generated before acceptance")
        app.buttons["إغلاق"].tap()
        XCTAssertFalse(app.buttons["workout.finish"].exists)
        openGenerator(app)
        reveal(equipment, in: app)
        equipment.tap()
        reveal(dumbbells, in: app)
        XCTAssertEqual(dumbbells.value as? String, "متاح")
        XCTAssertEqual(bench.value as? String, "متاح")
        let barbell = app.buttons["smart.equipment.barbell"]
        XCTAssertEqual(barbell.value as? String, "غير متاح")
        capture(app, name: "Arabic exact equipment preferences retained after cancelling preview")
        app.buttons["تم"].tap()
        app.buttons["إغلاق"].tap()
        app.tabBars.buttons["تقدّمي"].tap()
        let completed = app.descendants(matching: .any).matching(identifier: "progress.completed").firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertTrue(completed.label.contains("٠") || completed.label.contains("0"))
        let recovery = app.buttons["progress.recovery"]
        reveal(recovery, in: app)
        recovery.tap()
        XCTAssertTrue(app.navigationBars["استشفاء العضلات"].waitForExistence(timeout: 5))
        capture(app, name: "Arabic gray muscle map before any workout")
        let readiness = app.staticTexts["recovery.detail.readiness"]
        reveal(readiness, in: app)
        XCTAssertTrue(readiness.label.contains("غير محدد"))
        capture(app, name: "Arabic unknown recovery before any completed workout")
    }

    @MainActor private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launchEnvironment["FITNESS_TESTING"] = "1"
        app.launchEnvironment["FITNESS_TEST_THEME"] = ProcessInfo.processInfo.environment["UI_TEST_THEME"] ?? "system"
        app.launchEnvironment["FITNESS_TEST_DIGITS"] = ProcessInfo.processInfo.environment["UI_TEST_DIGITS"] ?? "arabic"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["التمرين"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func openGenerator(_ app: XCUIApplication) {
        let open = app.buttons["workout.smart"]
        reveal(open, in: app)
        open.tap()
        XCTAssertTrue(app.navigationBars["تمرين مقترح"].waitForExistence(timeout: 5))
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<12 where !element.exists || !element.isHittable {
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func allowNotificationIfShown() {
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 5) {
            let allow = ["السماح", "Allow", "حسنًا", "OK"].map { permission.buttons[$0] }.first { $0.exists }
            XCTAssertNotNil(allow)
            allow?.tap()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !permission.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        }
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(data: app.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
}
