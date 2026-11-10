import Foundation
import Security

enum KeychainError: Error, Sendable {
    case unexpectedStatus(OSStatus)
    case dataCorruption
}

/// Items are kept on this device only, never synced through iCloud Keychain.
/// Builds up to 0.20.0 saved them synced, so reads and removals can name
/// that kind too.
enum KeychainStore {
    enum Kind {
        case thisDeviceOnly
        case synced
        /// Both kinds, for removing an item whichever way it was saved.
        case either

        fileprivate var synchronizable: CFTypeRef {
            switch self {
            case .thisDeviceOnly: kCFBooleanFalse!
            case .synced: kCFBooleanTrue!
            case .either: kSecAttrSynchronizableAny
            }
        }
    }

    static func save(_ data: Data, account: String, service: String) throws {
        let base = query(account: account, service: service, kind: .thisDeviceOnly)
        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func load(account: String, service: String, kind: Kind = .thisDeviceOnly) throws -> Data? {
        var query = query(account: account, service: service, kind: kind)
        query[kSecReturnData as String] = kCFBooleanTrue!
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainError.dataCorruption
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func remove(account: String, service: String, kind: Kind = .either) throws {
        let query = query(account: account, service: service, kind: kind)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func query(account: String, service: String, kind: Kind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kind.synchronizable,
        ]
    }
}
