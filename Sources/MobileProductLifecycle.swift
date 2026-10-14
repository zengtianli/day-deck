import Foundation

// Product allowlist and release channel; shared lifecycle code owns transfer/checking.
enum MobileProductLifecycle {
    static let productID = "day-deck"
    static let storeID = "6807048407"
    static var channel: MobileUpdateChannel { .appStore(id: storeID) }
    static var preferencesURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notihub/preferences.json")
    }
    static func makeConfiguration(defaults: UserDefaults = .standard, file: URL = preferencesURL) -> AppConfiguration {
        AppConfiguration(productID: productID, files: [AppConfigurationFile(url: file, keys: ["startupTab"]) { value in
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  (0...3).contains(number.intValue), number.doubleValue == Double(number.intValue) else {
                throw AppUpdateError("启动页面必须是今天、通知、随手记或连接；原配置已保留。")
            }
        }], defaults: defaults)
    }
    static let configuration = makeConfiguration()
    static var startupTab: Int { readStartupTab(from: preferencesURL) }
    static func readStartupTab(from file: URL) -> Int {
        guard let data = try? Data(contentsOf: file),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tab = value["startupTab"] as? Int, (0...3).contains(tab) else { return 0 }
        return tab
    }
}
