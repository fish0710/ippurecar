import Foundation
import CFNetwork

/// 读取系统代理设置的人类可读描述
enum ProxyInfo {
    static func systemDescription() -> String {
        guard let cf = CFNetworkCopySystemProxySettings()?.takeRetainedValue(),
              let dict = cf as? [String: Any] else { return "无" }

        func enabled(_ key: String) -> Bool {
            if let n = dict[key] as? NSNumber { return n.intValue != 0 }
            return false
        }
        func hostPort(_ label: String, _ prefix: String) -> String? {
            guard enabled("\(prefix)Enable"), let host = dict["\(prefix)Proxy"] as? String else { return nil }
            if let port = (dict["\(prefix)Port"] as? NSNumber)?.intValue {
                return "\(label) \(host):\(port)"
            }
            return "\(label) \(host)"
        }

        var parts: [String] = []
        if let s = hostPort("HTTPS", "HTTPS") { parts.append(s) }
        if let s = hostPort("HTTP", "HTTP") { parts.append(s) }
        if let s = hostPort("SOCKS", "SOCKS") { parts.append(s) }
        if enabled("ProxyAutoConfigEnable") { parts.append("PAC") }
        return parts.isEmpty ? "无" : parts.joined(separator: ", ")
    }

    /// 结合当前网络模式的描述
    static func description(for mode: NetworkMode) -> String {
        switch mode {
        case .system: return systemDescription()
        case .direct: return "直连（已忽略系统代理：\(systemDescription())）"
        }
    }
}
