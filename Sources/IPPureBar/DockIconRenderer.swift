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

    private static let center = NSPoint(x: 256, y: 282)
    private static let ringRadius: CGFloat = 150
    private static let ringWidth: CGFloat = 22
    private static let grayRing = NSColor(white: 0.62, alpha: 1)

    private static func draw(_ state: DockIconState) {
        let isNormal: Bool
        if case .error = state { isNormal = false } else { isNormal = true }
        drawBackground(gray: !isNormal)

        switch state {
        case .loading:
            drawRing(fraction: 1, color: grayRing, trackAlpha: 0.10, progressAlpha: 0.35)
            drawText("…", font: roundedFont(size: 150, weight: .bold),
                     color: NSColor(white: 1, alpha: 0.75), at: NSPoint(x: 256, y: 290))
            drawCapsule("加载中", tint: grayRing)
        case .error:
            drawRing(fraction: 0, color: grayRing, trackAlpha: 0.12, progressAlpha: 0)
            drawText("!", font: roundedFont(size: 220, weight: .heavy),
                     color: NSColor(white: 1, alpha: 0.9), at: NSPoint(x: 256, y: 290))
            drawCapsule("请求失败", tint: grayRing)
        case .loaded(let info):
            let level = info.riskLevel
            let color = level?.color ?? grayRing
            let fraction = CGFloat(min(max(info.fraudScore ?? 0, 0), 100)) / 100
            drawRing(fraction: fraction, color: color, trackAlpha: 0.10, progressAlpha: 1)
            drawText(info.flag, font: NSFont(name: "Apple Color Emoji", size: 104) ?? .systemFont(ofSize: 104),
                     color: .white, at: NSPoint(x: 256, y: 350))
            let scoreText = info.fraudScore.map { String($0) } ?? "--"
            drawText(scoreText, font: roundedFont(size: 112, weight: .heavy),
                     color: .white, at: NSPoint(x: 256, y: 232))
            drawCapsule(info.shortSummary, tint: color)
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

    private static func drawCapsule(_ text: String, tint: NSColor) {
        let font = NSFont.systemFont(ofSize: 38, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let height: CGFloat = 60
        let width = min(size.width + 48, 420)
        let rect = NSRect(x: 256 - width / 2, y: 50, width: width, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
        tint.withAlphaComponent(0.30).setFill()
        path.fill()
        tint.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        str.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
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
