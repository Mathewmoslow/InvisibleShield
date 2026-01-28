import Foundation
import LocalAuthentication
import Combine
import AppKit

// MARK: - Authentication Errors
enum AuthenticationError: LocalizedError {
    case biometricNotAvailable
    case biometricNotEnrolled
    case authenticationFailed(String)
    case sessionExpired
    case cancelled
    case passcodeNotSet
    case systemError(Error)

    var errorDescription: String? {
        switch self {
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device."
        case .biometricNotEnrolled:
            return "No biometric data is enrolled. Please set up Touch ID or Face ID in System Preferences."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .sessionExpired:
            return "Your session has expired. Please authenticate again."
        case .cancelled:
            return "Authentication was cancelled."
        case .passcodeNotSet:
            return "Device passcode is not set. Please set a passcode in System Preferences."
        case .systemError(let error):
            return "System error: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .biometricNotAvailable, .biometricNotEnrolled:
            return "You can use your device passcode as a fallback."
        case .sessionExpired:
            return "Tap to authenticate with Touch ID or your passcode."
        case .passcodeNotSet:
            return "Set up a passcode in System Preferences > Security & Privacy."
        default:
            return nil
        }
    }
}

// MARK: - Authentication State
enum AuthenticationState: Equatable {
    case unauthenticated
    case authenticating
    case authenticated(expiresAt: Date)
    case failed(String)

    var isAuthenticated: Bool {
        if case .authenticated(let expiresAt) = self {
            return Date() < expiresAt
        }
        return false
    }

    static func == (lhs: AuthenticationState, rhs: AuthenticationState) -> Bool {
        switch (lhs, rhs) {
        case (.unauthenticated, .unauthenticated):
            return true
        case (.authenticating, .authenticating):
            return true
        case (.authenticated(let lhsDate), .authenticated(let rhsDate)):
            return lhsDate == rhsDate
        case (.failed(let lhsMsg), .failed(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

// MARK: - Configuration
struct AuthenticationConfiguration {
    let sessionTimeout: TimeInterval
    let allowPasscodeFallback: Bool
    let localizedReason: String

    static let `default` = AuthenticationConfiguration(
        sessionTimeout: 300, // 5 minutes
        allowPasscodeFallback: true,
        localizedReason: "Authenticate to access Whisper Wire secure features"
    )
}

// MARK: - AuthenticationManager
final class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    // MARK: - Published State
    @Published private(set) var state: AuthenticationState = .unauthenticated
    @Published private(set) var lastError: AuthenticationError?

    // MARK: - Configuration
    var configuration: AuthenticationConfiguration = .default

    // MARK: - Private Properties
    private var sessionTimer: Timer?
    private var currentContext: LAContext?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupSessionMonitoring()
    }

    // MARK: - Public API

    /// Authenticates the user with biometrics (or passcode fallback)
    /// Returns the LAContext for Keychain operations
    @MainActor
    func authenticate() async throws -> LAContext {
        // Check if already authenticated
        if state.isAuthenticated, let context = currentContext {
            return context
        }

        state = .authenticating
        lastError = nil

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = configuration.allowPasscodeFallback ? "Use Passcode" : ""

        // Check biometric/passcode availability
        var error: NSError?
        let policy: LAPolicy = configuration.allowPasscodeFallback
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        guard context.canEvaluatePolicy(policy, error: &error) else {
            let authError = mapLAError(error)
            state = .failed(authError.errorDescription ?? "Unknown error")
            lastError = authError
            throw authError
        }

        // Perform authentication
        do {
            let success = try await context.evaluatePolicy(
                policy,
                localizedReason: configuration.localizedReason
            )

            if success {
                let expiresAt = Date().addingTimeInterval(configuration.sessionTimeout)
                currentContext = context
                state = .authenticated(expiresAt: expiresAt)
                startSessionTimer(expiresAt: expiresAt)
                return context
            } else {
                let authError = AuthenticationError.authenticationFailed("Unknown reason")
                state = .failed(authError.errorDescription ?? "Failed")
                lastError = authError
                throw authError
            }
        } catch let laError as LAError {
            let authError = mapLAError(laError)
            state = .failed(authError.errorDescription ?? "Failed")
            lastError = authError
            throw authError
        } catch {
            let authError = AuthenticationError.systemError(error)
            state = .failed(authError.errorDescription ?? "Failed")
            lastError = authError
            throw authError
        }
    }

    /// Checks if biometric authentication is available
    func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Gets the type of biometric available
    func biometricType() -> LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    /// Invalidates the current session
    func invalidateSession() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        currentContext?.invalidate()
        currentContext = nil
        DispatchQueue.main.async {
            self.state = .unauthenticated
        }
    }

    /// Extends the current session if authenticated
    func extendSession() {
        guard state.isAuthenticated else { return }
        let newExpiry = Date().addingTimeInterval(configuration.sessionTimeout)
        state = .authenticated(expiresAt: newExpiry)
        startSessionTimer(expiresAt: newExpiry)
    }

    /// Returns the current LAContext if authenticated (for Keychain operations)
    var authenticatedContext: LAContext? {
        guard state.isAuthenticated else { return nil }
        return currentContext
    }

    // MARK: - Private Implementation

    private func setupSessionMonitoring() {
        // Monitor for app going to background (optional: invalidate session)
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                // Optional: Uncomment to invalidate session when app loses focus
                // self?.invalidateSession()
                _ = self
            }
            .store(in: &cancellables)
    }

    private func startSessionTimer(expiresAt: Date) {
        sessionTimer?.invalidate()

        let interval = expiresAt.timeIntervalSinceNow
        guard interval > 0 else {
            invalidateSession()
            return
        }

        sessionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.invalidateSession()
                self?.lastError = .sessionExpired
            }
        }
    }

    private func mapLAError(_ error: NSError?) -> AuthenticationError {
        guard let error = error else {
            return .authenticationFailed("Unknown error")
        }

        // Handle LAError codes
        if error.domain == LAError.errorDomain {
            let code = LAError.Code(rawValue: error.code)
            switch code {
            case .biometryNotAvailable:
                return .biometricNotAvailable
            case .biometryNotEnrolled:
                return .biometricNotEnrolled
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .userFallback:
                return .authenticationFailed("User chose passcode fallback")
            case .authenticationFailed:
                return .authenticationFailed("Biometric did not match")
            case .passcodeNotSet:
                return .passcodeNotSet
            default:
                return .authenticationFailed(error.localizedDescription)
            }
        }

        return .authenticationFailed(error.localizedDescription)
    }

    private func mapLAError(_ error: LAError) -> AuthenticationError {
        switch error.code {
        case .biometryNotAvailable:
            return .biometricNotAvailable
        case .biometryNotEnrolled:
            return .biometricNotEnrolled
        case .userCancel, .appCancel, .systemCancel:
            return .cancelled
        case .userFallback:
            return .authenticationFailed("User chose passcode fallback")
        case .authenticationFailed:
            return .authenticationFailed("Biometric did not match")
        case .passcodeNotSet:
            return .passcodeNotSet
        default:
            return .authenticationFailed(error.localizedDescription)
        }
    }
}
