import XCTest

final class RedesignFlowTests: XCTestCase {
    @MainActor func testCalendarAndLocalSettingsAreAccessibleAtLargestTypeSize() {
        continueAfterFailure = false
        let app = launch(largeType: true)
        capture(app, "Modern Arabic dashboard largest Dynamic Type")
        let calendar = app.buttons["dashboard.calendar"]
        reveal(calendar, app: app); calendar.tap()
        XCTAssertTrue(app.navigationBars["تقويم الإنجاز"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["الأرقام الشخصية"].exists)
        XCTAssertTrue(app.buttons["الشهر السابق"].isHittable)
        capture(app, "Accessible Arabic monthly calendar")
        app.buttons["الشهر السابق"].tap()
        app.buttons["الشهر التالي"].tap()
        app.tabBars.buttons["الإعدادات"].tap()
        XCTAssertFalse(app.switches["ربط تطبيق الصحة"].exists)
        XCTAssertFalse(app.buttons["فحص حساب آي كلاود"].exists)
        let local = app.descendants(matching: .any).matching(identifier: "settings.sync.status").firstMatch
        reveal(local, app: app)
        XCTAssertTrue(local.label.contains("البيانات محفوظة على هذا الجهاز"))
        capture(app, "Modern local-only settings largest Dynamic Type")
    }
    @MainActor func testCompletionCardCanOpenNativeImageShareSheet() {
        continueAfterFailure = false
        let app = launch()
        capture(app, "Modern Arabic dashboard")
        let calendar = app.buttons["dashboard.calendar"]
        reveal(calendar, app: app); calendar.tap()
        XCTAssertTrue(app.navigationBars["تقويم الإنجاز"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["الأرقام الشخصية"].exists)
        capture(app, "Modern Arabic monthly achievement grid")
        app.navigationBars["تقويم الإنجاز"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["التمرين"].waitForExistence(timeout: 5))
        let start = app.buttons["workout.start"]; reveal(start, app: app); start.tap()
        let finish = app.buttons["workout.finish"]; reveal(finish, app: app); finish.tap()
        app.alerts.buttons["إنهاء وحفظ"].tap()
        let share = app.buttons["workout.summary.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 10)); reveal(share, app: app); share.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5) || app.buttons["Copy"].exists || app.buttons["نسخ"].exists || app.buttons["Close"].exists || app.buttons["إغلاق"].exists)
        capture(app, "Native achievement image sharing")
    }
    @MainActor private func launch(largeType: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launchEnvironment["FITNESS_TESTING"] = "1"
        app.launchEnvironment["FITNESS_TEST_THEME"] = ProcessInfo.processInfo.environment["UI_TEST_THEME"] ?? "light"
        app.launchEnvironment["FITNESS_TEST_DIGITS"] = ProcessInfo.processInfo.environment["UI_TEST_DIGITS"] ?? "arabic"
        if largeType { app.launchEnvironment["FITNESS_TEST_LARGE_TYPE"] = "1"; app.launchEnvironment["FITNESS_TEST_REDUCE_MOTION"] = "1" }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["التمرين"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<24 {
            let navBottom = app.navigationBars.firstMatch.frame.maxY
            let tabTop = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : .infinity
            let top = navBottom.isFinite ? min(max(navBottom + 8, app.frame.height * 0.1), app.frame.height * 0.4) : app.frame.height * 0.14
            let bottom = tabTop.isFinite ? max(tabTop - 8, app.frame.height * 0.6) : app.frame.maxY - 60
            if element.exists && element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { break }
            let up = !element.exists || element.frame.maxY > bottom
            let from = CGPoint(x: app.frame.midX, y: up ? bottom - 60 : top + 70)
            let to = CGPoint(x: app.frame.midX, y: up ? top + 70 : bottom - 60)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: from.x, dy: from.y)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: to.x, dy: to.y)), withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(data: app.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + " accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
