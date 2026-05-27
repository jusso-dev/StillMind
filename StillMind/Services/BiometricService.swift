import LocalAuthentication

/// Manages FaceID/TouchID authentication following Apple's recommended pattern.
final class BiometricService: @unchecked Sendable {
    static let shared = BiometricService()

    private init() {}

    /// Returns the type of biometric available (Face ID, Touch ID, or none).
    func biometricType() -> LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    /// Authenticates the user. Tries biometrics first; if unavailable, falls back to passcode.
    /// This follows Apple's recommended pattern from the LocalAuthentication docs:
    /// 1. Check canEvaluatePolicy for biometrics
    /// 2. If available, evaluatePolicy with biometrics-only
    /// 3. If not available (locked out / not enrolled), evaluatePolicy with device owner (passcode)
    func authenticate(reason: String = "Unlock your journal") async throws -> Bool {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            // Biometrics available — present Face ID / Touch ID
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } else {
            // Biometrics unavailable (not enrolled, locked out, etc.) — use passcode
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        }
    }
}
