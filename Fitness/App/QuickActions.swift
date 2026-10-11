import UIKit

enum WorkoutQuickAction: String, CaseIterable {
    case today, free, progress
    init?(shortcutType: String) {
        guard let suffix = shortcutType.split(separator: ".").last else { return nil }
        self.init(rawValue: String(suffix))
    }
}

@MainActor enum QuickActionRouter {
    @discardableResult static func enqueue(_ item: UIApplicationShortcutItem) -> Bool {
        guard let action = WorkoutQuickAction(shortcutType: item.type) else { return false }
        if action == .today {
            UserDefaults.standard.removeObject(forKey: "pendingWorkoutAction")
            SharedWorkoutStorage.requestStartToday()
        } else {
            UserDefaults.standard.removeObject(forKey: "pendingStartToday")
            UserDefaults.standard.set(action.rawValue, forKey: "pendingWorkoutAction")
        }
        NotificationCenter.default.post(name: .workoutShortcutRequested, object: nil)
        return true
    }
}

@MainActor final class WateeraAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { QuickActionRouter.enqueue(item) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .windowApplication { configuration.delegateClass = WateeraSceneDelegate.self }
        return configuration
    }
}

@MainActor final class WateeraSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor item: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(QuickActionRouter.enqueue(item))
    }
}
