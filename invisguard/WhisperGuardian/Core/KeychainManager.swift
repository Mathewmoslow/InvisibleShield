import Foundation
import Security
import LocalAuthentication

// MARK: - Keychain Errors
enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case invalidItemFormat
    case unexpectedStatus(OSStatus)
    case accessControlCreationFailed
    case keyGenerationFailed
    case biometricNotAvailable
    case authenticationFailed(String)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "The requested item was not found in the Keychain."
        case .duplicateItem:
            return "An item with this identifier already exists."
        case .invalidItemFormat:
            return "The Keychain item data format is invalid."
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status: \(status)"
        case .accessControlCreationFailed:
            return "Failed to create access control for biometric protection."
        case .keyGenerationFailed:
            return "Failed to generate a secure encryption key."
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        }
    }
}

// MARK: - KeychainManager
final class KeychainManager {
    static let shared = KeychainManager()

    // MARK: - Constants
    private let vaultKeyTag = "com.whisperwire.invisguard.vaultKey"
    private let keyLength = 32 // 256 bits for AES-256
    private let service = "com.whisperwire.invisguard"

    private init() {}

    // MARK: - Public API

    /// Retrieves or creates the vault encryption key with biometric protection
    /// - Parameter context: Optional LAContext for reusing authenticated session
    /// - Returns: 256-bit encryption key
    func getOrCreateVaultKey(context: LAContext? = nil) throws -> Data {
        do {
            return try retrieveKey(context: context)
        } catch KeychainError.itemNotFound {
            return try createAndStoreKey()
        }
    }

    /// Checks if a vault key exists without retrieving it
    func vaultKeyExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultKeyTag,
            kSecReturnData as String: false
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Deletes the vault key (use with caution - encrypted data will be unrecoverable)
    func deleteVaultKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultKeyTag
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Private Implementation

    private func retrieveKey(context: LAContext? = nil) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultKeyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // Use provided LAContext if available (for session reuse)
        if let context = context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.invalidItemFormat
            }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        case errSecUserCanceled:
            throw KeychainError.authenticationFailed("User cancelled")
        case errSecAuthFailed:
            throw KeychainError.authenticationFailed("Authentication failed")
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func createAndStoreKey() throws -> Data {
        // Generate cryptographically secure random key
        var keyData = Data(count: keyLength)
        let result = keyData.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, keyLength, ptr.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw KeychainError.keyGenerationFailed
        }

        // Create access control requiring biometric or passcode authentication
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.biometryCurrentSet, .or, .devicePasscode],
            &error
        ) else {
            throw KeychainError.accessControlCreationFailed
        }

        // Store in Keychain with biometric protection
        // Create a fresh LAContext for the store operation
        let context = LAContext()
        context.interactionNotAllowed = false

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultKeyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessControl as String: accessControl,
            kSecUseAuthenticationContext as String: context
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return keyData
        case errSecDuplicateItem:
            // Key was created by another thread, retrieve it
            return try retrieveKey()
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
