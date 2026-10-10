import Foundation
import LocalAuthentication
import Observation

@Observable
@MainActor
final class AppLockService {
    private(set) var isUnlocked = false
    private(set) var isAuthenticating = false
    var errorMessage: String?
    @ObservationIgnored private var context: LAContext?
    @ObservationIgnored private var authenticationID: UUID?

    func lock() {
        context?.invalidate()
        context = nil
        authenticationID = nil
        isAuthenticating = false
        isUnlocked = false
    }

    // Lock on background, not inactive: Face ID itself transitions the scene to inactive.
    func sceneDidEnterBackground(enabled: Bool) {
        if enabled { lock() }
    }

    func disableLock() {
        context?.invalidate()
        context = nil
        authenticationID = nil
        isAuthenticating = false
        isUnlocked = true
        errorMessage = nil
    }

    @discardableResult
    func unlock(reason: String = "افتح وتيرة للوصول إلى بيانات تمارينك.") async -> Bool {
        guard !isAuthenticating else { return false }
        let requestID = UUID()
        let authenticationContext = LAContext()
        authenticationContext.localizedCancelTitle = "إلغاء"
        authenticationContext.localizedFallbackTitle = "استخدم رمز الدخول"
        var capabilityError: NSError?
        guard authenticationContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &capabilityError) else {
            errorMessage = "فعّل رمز دخول الجهاز أو بصمة الوجه لاستخدام القفل."
            return false
        }
        context = authenticationContext
        authenticationID = requestID
        isAuthenticating = true
        errorMessage = nil
        do {
            let authenticated = try await authenticationContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            guard authenticationID == requestID else { return false }
            isUnlocked = authenticated
            isAuthenticating = false
            context = nil
            return authenticated
        } catch {
            guard authenticationID == requestID else { return false }
            isAuthenticating = false
            context = nil
            let code = (error as? LAError)?.code
            if code != .userCancel && code != .appCancel && code != .systemCancel {
                errorMessage = "تعذر التحقق من هويتك. حاول مجددًا أو استخدم رمز دخول الجهاز."
            }
            return false
        }
    }
}
