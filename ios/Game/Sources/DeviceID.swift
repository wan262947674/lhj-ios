import Foundation
import Security
import UIKit

/// 设备唯一标识：首次启动生成 UUID 存 Keychain，卸载重装不丢失。
/// 与安卓 Settings.Secure.android_id 行为对齐。
enum DeviceID {

    private static let service = "lhj.baolei.in.DeviceID"
    private static let account = "device-id"

    static let value: String = {
        // 1. 先查 Keychain
        if let existing = loadFromKeychain() {
            return existing
        }
        // 2. 再查旧的 UserDefaults（兼容升级）
        let defaults = UserDefaults.standard
        if let old = defaults.string(forKey: "deviceID"), !old.isEmpty {
            saveToKeychain(old)
            return old
        }
        // 3. 再查 identifierForVendor（iOS 2013+ 一直有，同设备同签名稳定）
        if let vendor = UIDevice.current.identifierForVendor?.uuidString {
            saveToKeychain(vendor)
            defaults.set(vendor, forKey: "deviceID")
            return vendor
        }
        // 4. 都没有，自己生成一个存起来
        let new = UUID().uuidString
        saveToKeychain(new)
        defaults.set(new, forKey: "deviceID")
        return new
    }()

    private static func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private static func saveToKeychain(_ value: String) {
        // 先删旧的（如果有）
        let delQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(delQuery as CFDictionary)

        // 再存新的
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: value.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }
}
