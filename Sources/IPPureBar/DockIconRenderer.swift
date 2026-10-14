import AppKit

enum DockIconState {
    case loading
    case error
    case loaded(IPInfo)
}

/// 动态绘制 Dock 图标（逻辑尺寸 512×512，可按 pixels 放大输出）
enum DockIconRenderer {
    static let logicalSize: CGFloat = 512

    static func image(for state: DockIconState) -> NSImage {
        let rep = bitmap(for: state, pixels: 1024)
        let image = NSImage(size: NSSize(width: logicalSize, height: logicalSize))
        image.addRepresentation(rep)
        return image
    }

    static func pngData(for state: DockIconState, pixels: Int = 512) -> Data? {
        bitmap(for: state, pixels: pixels).representation(using: .png, properties: [:])
    }

    static func bitmap(for state: DockIconState, pixels: Int = 512) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: logicalSize, height: logicalSize)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return rep }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        draw(state)
        return rep
    }

    // MARK: 绘制

    // 上半部：分数环（国旗 + 分数）；下半部：IP 铭牌
    private static let center = NSPoint(x: 256, y: 322)
    private static let ringRadius: CGFloat = 112
    private static let ringWidth: CGFloat = 20
    private static let plateRect = NSRect(x: 64, y: 64, width: 384, height: 104)
    private static let grayRing = NSColor(white: 0.62, alpha: 1)

    private static func draw(_ state: DockIconState) {
        let isNormal: Bool
        if case .error = state { isNormal = false } else { isNormal = true }
        drawBackground(gray: !isNormal)

        switch state {
        case .loading:
            drawRing(fraction: 1, color: grayRing, trackAlpha: 0.10, progressAlpha: 0.35)
            drawText("…", font: roundedFont(size: 130, weight: .bold),
                     color: NSColor(white: 1, alpha: 0.75), at: NSPoint(x: 256, y: 330))
            drawPlate(["加载中"], tint: grayRing)
        case .error:
            drawRing(fraction: 0, color: grayRing, trackAlpha: 0.12, progressAlpha: 0)
            drawText("!", font: roundedFont(size: 180, weight: .heavy),
                     color: NSColor(white: 1, alpha: 0.9), at: NSPoint(x: 256, y: 326))
            drawPlate(["请求失败"], tint: grayRing)
        case .loaded(let info):
            let level = info.riskLevel
            let color = level?.color ?? grayRing
            let fraction = CGFloat(min(max(info.fraudScore ?? 0, 0), 100)) / 100
            drawRing(fraction: fraction, color: color, trackAlpha: 0.10, progressAlpha: 1)
            drawText(info.flag, font: NSFont(name: "Apple Color Emoji", size: 72) ?? .systemFont(ofSize: 72),
                     color: .white, at: NSPoint(x: 256, y: 372))
            let scoreText = info.fraudScore.map { String($0) } ?? "--"
            drawText(scoreText, font: roundedFont(size: 96, weight: .heavy),
                     color: .white, at: NSPoint(x: 256, y: 292))
            drawPlate(ipLines(info.ip), tint: color)
        }
    }

    private static func drawBackground(gray: Bool) {
        let rect = NSRect(x: 36, y: 36, width: 440, height: 440)
        let path = NSBezierPath(roundedRect: rect, xRadius: 100, yRadius: 100)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.shadowBlurRadius = 14
        shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow.set()
        NSColor.black.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        let top = gray ? NSColor(srgbRed: 0.34, green: 0.35, blue: 0.39, alpha: 1)
                       : NSColor(srgbRed: 0.17, green: 0.18, blue: 0.23, alpha: 1)
        let bottom = gray ? NSColor(srgbRed: 0.22, green: 0.23, blue: 0.26, alpha: 1)
                          : NSColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)

        // 顶部细高光
        NSColor(white: 1, alpha: 0.08).setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private static func drawRing(fraction: CGFloat, color: NSColor, trackAlpha: CGFloat, progressAlpha: CGFloat) {
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
        track.lineWidth = ringWidth
        NSColor(white: 1, alpha: trackAlpha).setStroke()
        track.stroke()

        guard fraction > 0 else { return }
        let arc = NSBezierPath()
        if fraction >= 1 {
            arc.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
        } else {
            arc.appendArc(withCenter: center, radius: ringRadius,
                          startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
        }
        arc.lineWidth = ringWidth
        arc.lineCapStyle = .round
        color.withAlphaComponent(progressAlpha).setStroke()
        arc.stroke()
    }

    /// IPv4 单行；IPv6 单行放不下时从中间的冒号处拆成两行
    private static func ipLines(_ ip: String?) -> [String] {
        guard let ip, !ip.isEmpty else { return ["--"] }
        guard ip.contains(":"), plateFontSize(for: [ip]) < 44 else { return [ip] }
        let groups = ip.split(separator: ":", omittingEmptySubsequences: false)
        let half = (groups.count + 1) / 2
        return [groups[..<half].joined(separator: ":") + ":", groups[half...].joined(separator: ":")]
    }

    private static func plateFont(size: CGFloat) -> NSFont {
        let base = roundedFont(size: size, weight: .bold)
        let desc = base.fontDescriptor.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
        ]]])
        return NSFont(descriptor: desc, size: size) ?? base
    }

    /// 在铭牌内能容纳所有行的最大字号（上限 72）
    private static func plateFontSize(for lines: [String]) -> CGFloat {
        let maxWidth = plateRect.width - 36
        let maxHeight = (plateRect.height - 16) / CGFloat(lines.count)
        let probe: CGFloat = 100
        let widest = lines.map {
            NSAttributedString(string: $0, attributes: [.font: plateFont(size: probe)]).size().width
        }.max() ?? 1
        return min(72, probe * maxWidth / widest, maxHeight / 1.2)
    }

    private static func drawPlate(_ lines: [String], tint: NSColor) {
        let path = NSBezierPath(roundedRect: plateRect, xRadius: 28, yRadius: 28)
        tint.withAlphaComponent(0.24).setFill()
        path.fill()
        tint.withAlphaComponent(0.60).setStroke()
        path.lineWidth = 2
        path.stroke()

        let font = plateFont(size: plateFontSize(for: lines))
        let lineHeight = plateRect.height / CGFloat(lines.count + 1)
        for (i, line) in lines.enumerated() {
            let y = plateRect.maxY - lineHeight * CGFloat(i + 1)
            drawText(line, font: font, color: .white, at: NSPoint(x: plateRect.midX, y: y))
        }
    }

    private static func drawText(_ text: String, font: NSFont, color: NSColor, at point: NSPoint) {
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = str.size()
        str.draw(at: NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }

    private static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let desc = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: desc, size: size) {
            return f
        }
        return base
    }
}
