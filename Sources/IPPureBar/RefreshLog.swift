import Foundation

/// 刷新触发原因
enum RefreshTrigger: String, Sendable {
    case launch = "启动"
    case manual = "手动"
    case reopen = "点击 Dock"
    case timer = "定时"
    case network = "网络变化"
    case proxy = "代理变化"
    case wake = "唤醒"
    case modeChange = "切换模式"
}

/// 刷新结果日志：~/Library/Logs/IPPureBar/refresh.log，每次刷新一行，超过 1 MB 轮转为 refresh.log.1。
final class RefreshLog: Sendable {
    static let shared = RefreshLog()

    static let maxBytes = 1_000_000

    let fileURL: URL
    private let queue = DispatchQueue(label: "ippurebar.refreshlog")

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/IPPureBar", isDirectory: true)
        fileURL = dir.appendingPathComponent("refresh.log")
    }

    enum Outcome {
        case success(IPInfo)
        case failure(String)
        case cancelled
    }

    func record(trigger: RefreshTrigger, mode: NetworkMode, proxy: String,
                startedAt: Date, outcome: Outcome) {
        let duration = String(format: "%.2fs", Date().timeIntervalSince(startedAt))
        var parts = [
            Self.timestampFormatter.string(from: startedAt),
            "[\(trigger.rawValue)]",
            "模式=\(mode.rawValue)",
            "代理=\(proxy)",
            "|",
        ]
        switch outcome {
        case .success(let info):
            parts += ["成功", duration, "|",
                      "IP=\(info.ip ?? "—")",
                      "位置=\(info.locationText.isEmpty ? "—" : info.locationText)",
                      "ASN=\(info.asnText.isEmpty ? "—" : info.asnText)",
                      "风险=\(info.fraudScore.map(String.init) ?? "—")",
                      "类型=\(info.broadcastText)/\(info.residentialText)"]
        case .failure(let message):
            parts += ["失败", duration, "|", message]
        case .cancelled:
            parts += ["取消", duration, "|", "被新的刷新取代"]
        }
        append(parts.joined(separator: " ") + "\n")
    }

    private func append(_ line: String) {
        let url = fileURL
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > Self.maxBytes {
                let old = url.appendingPathExtension("1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
