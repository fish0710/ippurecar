import Foundation

enum IPInfoError: LocalizedError {
    case badStatus(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "服务器返回 HTTP \(code)"
        case .decoding(let msg): return "解析失败：\(msg)"
        }
    }
}

struct IPInfoClient: Sendable {
    static let endpoint = URL(string: "https://my.ippure.com/v1/info")!

    /// 每次请求新建 session，结束后失效，避免 keep-alive 沿用旧出口线路。
    func fetch(mode: NetworkMode) async throws -> IPInfo {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        if mode == .direct {
            config.connectionProxyDictionary = [:]
        }
        // mode == .system：不设置 connectionProxyDictionary，由 CFNetwork 自动应用系统代理（含 PAC）

        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw IPInfoError.badStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(IPInfo.self, from: data)
        } catch {
            throw IPInfoError.decoding(error.localizedDescription)
        }
    }
}
