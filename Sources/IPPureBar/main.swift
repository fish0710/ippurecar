import AppKit

setvbuf(stdout, nil, _IOLBF, 0)

// 构建脚本使用：渲染 1024px 静态应用图标后退出
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render-appicon"), i + 1 < args.count {
    let state = DockIconState.loaded(AppDelegate.sampleInfo(score: 12))
    guard let data = DockIconRenderer.pngData(for: state, pixels: 1024) else { exit(1) }
    do {
        try data.write(to: URL(fileURLWithPath: args[i + 1]))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("写入失败: \(error)\n".utf8))
        exit(1)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
