import Foundation

enum NetworkMode: String {
    /// 跟随系统代理（含 PAC）
    case system
    /// 直连，忽略系统代理
    case direct
}

/// UserDefaults 封装
final class Settings: @unchecked Sendable {
    static let shared = Settings()

    static let refreshChoices = [0, 1, 5, 15, 30]

    private enum Key {
        static let refreshMinutes = "refreshMinutes"
        static let networkMode = "networkMode"
        static let showInDock = "showInDock"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.refreshMinutes: 5,
            Key.networkMode: NetworkMode.system.rawValue,
            Key.showInDock: true,
        ])
    }

    /// 自动刷新间隔（分钟），0 表示关闭
    var refreshMinutes: Int {
        get { defaults.integer(forKey: Key.refreshMinutes) }
        set { defaults.set(newValue, forKey: Key.refreshMinutes) }
    }

    var networkMode: NetworkMode {
        get { NetworkMode(rawValue: defaults.string(forKey: Key.networkMode) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.networkMode) }
    }

    var showInDock: Bool {
        get { defaults.bool(forKey: Key.showInDock) }
        set { defaults.set(newValue, forKey: Key.showInDock) }
    }
}
