import Foundation
import Security

/// 手表 App 与表盘复杂功能**共用的一份**落盘：iPhone 递来的最近一份摘要（WatchDigest）。
///
/// 走手表本机钥匙串的共享组（Watch.entitlements / WatchWidget.entitlements 第一项逐字相同），不是 App Group：
/// App Group 要先在开发者门户登记，keychain access group 用 team 前缀通配、零登记（成长小金库同一做法）。
/// 故意**不传** kSecAttrAccessGroup：不传时落在 entitlements 的第一个组，两个 target 第一项写成同一个就是同一个仓。
/// 摘要里有通知原文的第一行，钥匙串比明文文件合适；AfterFirstUnlock 让表盘在手表锁着时也读得到。
enum DigestVault {
    private static let service = "cyou.tianli.daydeck.watch-digest"
    private static let account = "latest"

    struct Saved: Codable {
        let digest: WatchDigest
        let receivedAt: Date
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> Saved? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    static func save(_ saved: Saved) {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = baseQuery
            add.merge(attrs) { a, _ in a }
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
