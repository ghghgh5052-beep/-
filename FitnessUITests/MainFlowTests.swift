import XCTest

final class MainFlowTests: XCTestCase {
    @MainActor
    func testProductionStartupWithoutIntegrationEntitlements() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Exercise the production persistent-store/bootstrap path, not the in-memory UI fixture.
        app.launchArguments = ["-startup-smoke-test", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        let onboarding = app.buttons["onboarding.finish"]
        if onboarding.waitForExistence(timeout: 3) { onboarding.tap() }
        XCTAssertTrue(app.tabBars.buttons["خططي"].waitForExistence(timeout: 15))
        let title = app.navigationBars["التمرين"].staticTexts["التمرين"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["startup.warning"].exists)
        XCTAssertFalse(app.buttons["إخفاء التنبيه"].exists)
        capture(app, name: "Arabic local startup without signed integrations")
        app.tabBars.buttons["الإعدادات"].tap()
        let localStatus = app.descendants(matching: .any).matching(identifier: "settings.sync.status").firstMatch
        for _ in 0..<6 where !localStatus.isHittable { app.swipeUp() }
        XCTAssertTrue(localStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(localStatus.isHittable)
        XCTAssertTrue(localStatus.label.contains("البيانات محفوظة على هذا الجهاز"))
        capture(app, name: "Arabic local storage status in settings")
        let about = app.buttons["settings.about"]
        for _ in 0..<4 where !about.isHittable { app.swipeUp() }
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        XCTAssertTrue(about.isHittable)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "لا حسابات")).firstMatch.exists)
        about.tap()
        XCTAssertTrue(app.navigationBars["عن وتيرة"].waitForExistence(timeout: 5))
        let owner = app.staticTexts["app.owner.name"]
        for _ in 0..<4 where !owner.isHittable { app.swipeUp() }
        XCTAssertTrue(owner.waitForExistence(timeout: 5))
        XCTAssertTrue(owner.isHittable)
        XCTAssertEqual(owner.label, "Coach : 3BIID - AB")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "لا حسابات")).firstMatch.exists)
        capture(app, name: "Arabic app ownership")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["خططي"].waitForExistence(timeout: 15))
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["startup.warning"].exists)
    }

    @MainActor
    func testOfflineExerciseImagesCanBeViewedZoomedAndClosed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launchEnvironment["FITNESS_TESTING"] = "1"
        app.launchEnvironment["FITNESS_TEST_THEME"] = ProcessInfo.processInfo.environment["UI_TEST_THEME"] ?? "system"
        app.launchEnvironment["FITNESS_TEST_DIGITS"] = ProcessInfo.processInfo.environment["UI_TEST_DIGITS"] ?? "arabic"
        app.launch()
        let library = app.tabBars.buttons["المكتبة"]
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        library.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        if !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.isHittable)
        search.tap()
        search.typeText("ضغط الصدر بالبار")
        let benchPress = app.buttons["exercise.library.00000001-0000-4000-8000-000000000001"]
        XCTAssertTrue(benchPress.waitForExistence(timeout: 5))
        XCTAssertTrue(benchPress.isHittable)
        capture(app, name: "Arabic exercise library with offline thumbnails")
        benchPress.tap()
        XCTAssertTrue(app.navigationBars["تفاصيل التمرين"].waitForExistence(timeout: 5))
        let canvas = app.buttons["exercise.guide.image.0"]
        for _ in 0..<5 where !canvas.isHittable { app.swipeUp() }
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertTrue(canvas.isHittable)
        XCTAssertFalse(app.buttons["exercise.guide.image.1"].exists)
        let directions = app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "بداية", "نهاية", "اليمين", "اليسار")).firstMatch
        XCTAssertTrue(directions.waitForExistence(timeout: 5), "The Arabic caption must identify right/start and left/end")
        capture(app, name: "Arabic bench press start and end illustration canvas")
        canvas.tap()
        let close = app.buttons["exercise.guide.image.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let fullImage = app.images.containing(NSPredicate(format: "label CONTAINS %@", "ضغط الصدر بالبار")).firstMatch
        XCTAssertTrue(fullImage.waitForExistence(timeout: 5))
        capture(app, name: "Arabic full size bench press illustration canvas")
        let enlarge = app.buttons["تكبير الصورة"]
        let reduce = app.buttons["تصغير الصورة"]
        XCTAssertTrue(enlarge.isEnabled)
        XCTAssertFalse(reduce.isEnabled)
        enlarge.tap()
        let enlarged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in reduce.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [enlarged], timeout: 5), .completed)
        capture(app, name: "Arabic enlarged exercise image")
        reduce.tap()
        let originalSize = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !reduce.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [originalSize], timeout: 5), .completed)
        close.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !close.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        XCTAssertTrue(app.navigationBars["تفاصيل التمرين"].waitForExistence(timeout: 5))
        capture(app, name: "Arabic exercise details after closing image")
    }

    @MainActor
    func testCreatePlanLogWorkoutAndViewProgress() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launchEnvironment["FITNESS_TESTING"] = "1"
        app.launchEnvironment["FITNESS_TEST_THEME"] = ProcessInfo.processInfo.environment["UI_TEST_THEME"] ?? "system"
        app.launchEnvironment["FITNESS_TEST_DIGITS"] = ProcessInfo.processInfo.environment["UI_TEST_DIGITS"] ?? "arabic"
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
        capture(app, name: "Arabic plans")
        addPlan.tap()
        let template = app.buttons["planTemplate_ppl"]
        XCTAssertTrue(template.waitForExistence(timeout: 5)); template.tap()
        let name = app.textFields["plan.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        capture(app, name: "Arabic plan editor")
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
        capture(app, name: "Arabic workout logging")
        let pause = app.buttons["workout.pause"]
        XCTAssertTrue(pause.isHittable)
        pause.tap()
        let guide = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.exercise.guide.")).firstMatch
        for _ in 0..<5 where !guide.isHittable { app.swipeUp() }
        XCTAssertTrue(guide.isHittable)
        XCTAssertTrue(guide.isEnabled, "Read-only exercise guidance must remain available while paused")
        guide.tap()
        XCTAssertTrue(app.buttons["exercise.guide.image.0"].waitForExistence(timeout: 5))
        capture(app, name: "Arabic exercise illustration during paused workout")
        app.buttons["exercise.guide.done"].tap()
        for _ in 0..<6 where !pause.isHittable { app.swipeDown() }
        XCTAssertTrue(pause.isHittable)
        XCTAssertTrue(pause.label.contains("استئناف"))
        pause.tap()
        for _ in 0..<5 where !weight.isHittable { app.swipeUp() }
        XCTAssertTrue(weight.isHittable)
        weight.tap()
        weight.typeText("20")
        XCTAssertTrue(["20", "٢٠"].contains(weight.value as? String ?? ""), "Entered weight must replace the previous value")
        let hideKeyboard = app.buttons["إخفاء لوحة المفاتيح"]
        if hideKeyboard.isHittable { hideKeyboard.tap() }
        let complete = app.buttons.matching(identifier: "set.complete.0").firstMatch
        XCTAssertTrue(complete.exists); complete.tap()
        // Handle the system alert directly: replaying a generic application tap can open
        // the exercise guide after the rest timer changes the workout's layout.
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 5) {
            let allow = ["السماح", "Allow", "حسنًا", "OK"].map { permission.buttons[$0] }.first { $0.exists }
            XCTAssertNotNil(allow, "The notification permission must expose an allow action")
            allow?.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !permission.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        }
        if app.alerts.buttons["حسنًا"].exists { app.alerts.buttons["حسنًا"].tap() }
        XCTAssertTrue(complete.label.contains("إلغاء إنجاز الجولة"), "The logged set must remain completed after notification permission")
        XCTAssertFalse(app.buttons["exercise.guide.done"].exists, "Permission handling must keep the workout visible")
        capture(app, name: "Arabic completed set and rest timer")
        let finish = app.buttons["workout.finish"]
        for _ in 0..<12 where !finish.isHittable { app.swipeUp() }
        XCTAssertTrue(finish.exists); finish.tap()
        let confirm = app.buttons["إنهاء وحفظ"]
        if confirm.waitForExistence(timeout: 2) { confirm.tap() }
        let summaryDone = app.buttons["workout.summary.done"]
        XCTAssertTrue(summaryDone.waitForExistence(timeout: 10))
        let expectedVolume = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "٢٠٠ كجم", "200 كجم")).firstMatch
        XCTAssertTrue(expectedVolume.exists, "Saved volume must reflect 20 kg for 10 repetitions")
        capture(app, name: "Arabic saved workout summary")
        summaryDone.tap()
        app.tabBars.buttons["تقدّمي"].tap()
        XCTAssertTrue(app.otherElements["progress.screen"].waitForExistence(timeout: 10) || app.navigationBars["تقدّمك"].exists)
        let completed = app.descendants(matching: .any).matching(identifier: "progress.completed").firstMatch
        XCTAssertTrue(completed.exists)
        XCTAssertTrue(completed.label.contains("١") || completed.label.contains("1"))
        capture(app, name: "Arabic workout progress")
        let monthly = app.segmentedControls["progress.volumePeriod"].buttons["شهري"]
        revealChartElement(monthly, in: app); monthly.tap()
        let volumeChart = app.descendants(matching: .any).matching(identifier: "progress.volumeChart").firstMatch
        revealChartElement(volumeChart, in: app)
        capture(app, name: "Arabic monthly volume with clear two-line dates")
        revealChartElement(monthly, in: app)
        app.segmentedControls["progress.volumePeriod"].buttons["أسبوعي"].tap()
        revealChartElement(volumeChart, in: app)
        capture(app, name: "Arabic weekly volume with clear two-line dates")
        app.tabBars.buttons["التمرين"].tap()
        let history = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.history.")).firstMatch
        for _ in 0..<14 where !history.isHittable { app.swipeUp() }
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        let delete = app.buttons["workout.summary.delete"]
        for _ in 0..<14 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.isHittable); delete.tap()
        capture(app, name: "Arabic completed session deletion confirmation")
        app.alerts.buttons["تراجع"].tap()
        XCTAssertTrue(app.buttons["workout.summary.done"].exists)
        delete.tap()
        app.alerts.buttons["workout.delete.confirm"].tap()
        for _ in 0..<12 where !app.staticTexts["تاريخك يبدأ من هنا"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["تاريخك يبدأ من هنا"].waitForExistence(timeout: 10))
        XCTAssertFalse(history.exists)
        app.tabBars.buttons["تقدّمي"].tap()
        for _ in 0..<6 where !completed.isHittable { app.swipeDown() }
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertTrue(completed.label.contains("٠") || completed.label.contains("0"))
        XCTAssertTrue(app.staticTexts["كل مجموعة تصنع فرقًا"].exists)
        capture(app, name: "Arabic progress after deleting the only logged session")
    }

    @MainActor private func revealChartElement(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            let bottom = app.tabBars.firstMatch.frame.minY - 10
            let top = app.frame.height * 0.2
            if element.exists && element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { return }
            if element.exists && element.frame.minY < top { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable)
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(data: app.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
