import Foundation
import Security
import os

private let log = Logger(subsystem: "com.noamchuri.scribe", category: "mailbox")

/// Where the Claude connector link is kept.
@MainActor
protocol MailboxLinkStore: AnyObject {
    /// Nil when there is no link; throws when the Keychain can't be read
    /// right now (e.g. before the first unlock).
    func load() throws -> String?
    func save(_ link: String) throws
    func delete()
}

/// The link in the Keychain as a synchronizable item, so the iPhone and the
/// Mac share it through iCloud Keychain (same team and bundle id, so the
/// same default access group). Readable after first unlock, for background
/// refresh. A build without a Keychain entitlement (an unsigned Mac build)
/// keeps a local, unsynced copy instead.
@MainActor
final class KeychainMailboxLinkStore: MailboxLinkStore {
    private let service = "com.noamchuri.scribe.mailbox"
    private let account = "connectorLink"

    private var identity: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    func load() throws -> String? {
        var query = identity
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            return nil
        case errSecMissingEntitlement:
            return loadLocal()
        default:
            log.error("Keychain read failed: \(status)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func save(_ link: String) throws {
        delete()
        var item = identity
        item[kSecAttrSynchronizable as String] = true
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecValueData as String] = Data(link.utf8)
        item[kSecAttrLabel as String] = "Scribe — Claude connector link"
        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            log.info("No Keychain entitlement: the link stays on this device")
            status = SecItemAdd(local(item) as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            log.error("Keychain write failed: \(status)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func delete() {
        var query = identity
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecMissingEntitlement { SecItemDelete(local(identity) as CFDictionary) }
    }

    /// The unsynced fallback: the Mac's file-based login keychain.
    private func local(_ query: [String: Any]) -> [String: Any] {
        var query = query
        query.removeValue(forKey: kSecAttrSynchronizable as String)
        query.removeValue(forKey: kSecUseDataProtectionKeychain as String)
        return query
    }

    private func loadLocal() -> String? {
        var query = local(identity)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// UI tests: nothing touches the real Keychain, and every run starts unconnected.
@MainActor
final class MemoryMailboxLinkStore: MailboxLinkStore {
    private var link: String?

    func load() throws -> String? { link }
    func save(_ link: String) throws { self.link = link }
    func delete() { link = nil }
}
