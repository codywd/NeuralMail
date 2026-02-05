import Foundation
import Security

enum KeychainStore {
    static let service = "com.dostalcody.NeuralMail"

    static func setPassword(_ password: String, key: String) throws {
        let encoded = Data(password.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: encoded,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        if status != errSecItemNotFound {
            throw KeychainError(status: status)
        }

        var insertQuery = query
        insertQuery[kSecValueData as String] = encoded
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        if insertStatus != errSecSuccess {
            throw KeychainError(status: insertStatus)
        }
    }

    static func getPassword(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        if status != errSecSuccess {
            throw KeychainError(status: status)
        }

        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw KeychainError(status: status)
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain error: \(status)"
        }
    }
}

