import Foundation
import Security

/// 토큰 같은 민감 문자열을 Keychain(kSecClassGenericPassword)에 저장/조회/삭제한다.
/// - UserDefaults 와 달리 기기 잠금/탈옥 보호를 받고, 앱 삭제 시까지 안전하게 남는다.
/// - 접근성: `.afterFirstUnlock` → 부팅 후 한 번 잠금 해제하면 백그라운드에서도 읽힘
///   (백그라운드 업로드/리프레시에 필요). iCloud 동기화는 막아 기기 로컬에만 둔다.
enum KeychainStore {
    /// 같은 앱/디바이스 내 키 충돌 방지용 서비스 네임스페이스
    private static let service = "app.stardust.session"

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        // upsert: 기존 항목을 지우고 새로 넣어 중복(errSecDuplicateItem)을 피한다.
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)

        var insert = base
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    @discardableResult
    static func remove(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
