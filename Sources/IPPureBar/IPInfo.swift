import AppKit

/// /v1/info 的返回；所有字段都是可选，且对类型宽松（数字/字符串互转），缺字段不会导致解码失败。
struct IPInfo: Codable, Sendable {
    var ip: String?
    var asn: Int?
    var asOrganization: String?
    var country: String?
    var countryCode: String?
    var region: String?
    var regionCode: String?
    var city: String?
    var timezone: String?
    var longitude: String?
    var latitude: String?
    var postalCode: String?
    var fraudScore: Int?
    var isResidential: Bool?
    var isBroadcast: Bool?
    var userAgent: String?

    init(ip: String? = nil, asn: Int? = nil, asOrganization: String? = nil,
         country: String? = nil, countryCode: String? = nil, region: String? = nil,
         regionCode: String? = nil, city: String? = nil, timezone: String? = nil,
         longitude: String? = nil, latitude: String? = nil, postalCode: String? = nil,
         fraudScore: Int? = nil, isResidential: Bool? = nil, isBroadcast: Bool? = nil,
         userAgent: String? = nil) {
        self.ip = ip; self.asn = asn; self.asOrganization = asOrganization
        self.country = country; self.countryCode = countryCode; self.region = region
        self.regionCode = regionCode; self.city = city; self.timezone = timezone
        self.longitude = longitude; self.latitude = latitude; self.postalCode = postalCode
        self.fraudScore = fraudScore; self.isResidential = isResidential
        self.isBroadcast = isBroadcast; self.userAgent = userAgent
    }

    private enum CodingKeys: String, CodingKey {
        case ip, asn, asOrganization, country, countryCode, region, regionCode, city
        case timezone, longitude, latitude, postalCode, fraudScore
        case isResidential, isBroadcast, userAgent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ip = c.lenientString(.ip)
        asn = c.lenientInt(.asn)
        asOrganization = c.lenientString(.asOrganization)
        country = c.lenientString(.country)
        countryCode = c.lenientString(.countryCode)
        region = c.lenientString(.region)
        regionCode = c.lenientString(.regionCode)
        city = c.lenientString(.city)
        timezone = c.lenientString(.timezone)
        longitude = c.lenientString(.longitude)
        latitude = c.lenientString(.latitude)
        postalCode = c.lenientString(.postalCode)
        fraudScore = c.lenientInt(.fraudScore)
        isResidential = c.lenientBool(.isResidential)
        isBroadcast = c.lenientBool(.isBroadcast)
        userAgent = c.lenientString(.userAgent)
    }
}

private extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let v = try? decodeIfPresent(String.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return String(v) }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return String(v) }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return Int(v.rounded()) }
        if let s = try? decodeIfPresent(String.self, forKey: key), let d = Double(s) { return Int(d.rounded()) }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            switch s.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }
}

// MARK: - 风险分级

enum RiskLevel: Sendable {
    case low, medium, high, critical

    /// score 会被限制在 0...100
    init(score: Int) {
        switch min(max(score, 0), 100) {
        case ..<25: self = .low
        case 25..<50: self = .medium
        case 50..<75: self = .high
        default: self = .critical
        }
    }

    var title: String {
        switch self {
        case .low: return "低风险"
        case .medium: return "中风险"
        case .high: return "高风险"
        case .critical: return "极高风险"
        }
    }

    var color: NSColor {
        switch self {
        case .low: return NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case .medium: return NSColor(srgbRed: 1.00, green: 0.80, blue: 0.00, alpha: 1)
        case .high: return NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1)
        case .critical: return NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)
        }
    }
}

extension IPInfo {
    var riskLevel: RiskLevel? { fraudScore.map(RiskLevel.init(score:)) }

    /// 国旗 emoji；国家码无效时返回地球
    var flag: String { IPInfo.flagEmoji(countryCode: countryCode) }

    static func flagEmoji(countryCode: String?) -> String {
        guard let code = countryCode?.uppercased(), code.unicodeScalars.count == 2,
              code.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return "🌐" }
        var s = ""
        for u in code.unicodeScalars {
            if let r = Unicode.Scalar(0x1F1E6 + u.value - 65) { s.unicodeScalars.append(r) }
        }
        return s
    }

    /// 原生 / 广播
    var broadcastText: String { isBroadcast == true ? "广播" : "原生" }
    /// 住宅 / 机房
    var residentialText: String { isResidential == true ? "住宅" : "机房" }

    /// Tokyo, Tokyo, Japan
    var locationText: String {
        [city, region, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// AS2914 · NTT Communications Corporation
    var asnText: String {
        var parts: [String] = []
        if let asn { parts.append("AS\(asn)") }
        if let org = asOrganization, !org.isEmpty { parts.append(org) }
        return parts.joined(separator: " · ")
    }

    var coordinateText: String {
        switch (latitude, longitude) {
        case let (la?, lo?): return "\(la), \(lo)"
        default: return ""
        }
    }
}

// MARK: - 应用状态

enum FetchPhase {
    case loading
    case loaded
    case failed(String)
}

struct AppState {
    var phase: FetchPhase = .loading
    /// 最近一次成功获取的结果（出错时仍保留以便查看）
    var info: IPInfo?
    var updatedAt: Date?
}
