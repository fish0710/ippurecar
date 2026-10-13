import AppKit
import ServiceManagement

/// 调试选项：
///   --dump-icon <png>     或环境变量 IPPURE_DUMP_ICON：首次成功获取后写出 Dock 图标并打印 IPInfo
///   --dump-states <dir>   启动时写出 loading/error 及分数 5/35/60/90 的样例图标
struct DebugOptions {
    var dumpIconPath: String?
    var dumpStatesDir: String?

    static func parse() -> DebugOptions {
        var opts = DebugOptions()
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--dump-icon"), i + 1 < args.count { opts.dumpIconPath = args[i + 1] }
        if let i = args.firstIndex(of: "--dump-states"), i + 1 < args.count { opts.dumpStatesDir = args[i + 1] }
        if opts.dumpIconPath == nil, let env = ProcessInfo.processInfo.environment["IPPURE_DUMP_ICON"], !env.isEmpty {
            opts.dumpIconPath = env
        }
        return opts
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let client = IPInfoClient()
    private let scheduler = RefreshScheduler()
    private var debug = DebugOptions.parse()

    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()

    private(set) var state = AppState()
    private var fetchTask: Task<Void, Never>?
    private var generation = 0

    // MARK: 生命周期

    func applicationWillFinishLaunching(_ notification: Notification) {
        applyActivationPolicy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        statusMenu.delegate = self
        statusMenu.autoenablesItems = false
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = statusMenu
        statusItem.button?.toolTip = "IPPure Bar"

        render()
        dumpStatesIfNeeded()

        scheduler.onTrigger = { [weak self] in self?.refresh() }
        scheduler.start(intervalMinutes: settings.refreshMinutes)
        refresh()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        refresh()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MenuBuilder.dockMenu(state: state, settings: settings, target: self)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        MenuBuilder.fill(statusMenu: menu, state: state, settings: settings,
                         launchAtLogin: SMAppService.mainApp.status == .enabled, target: self)
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
    }

    /// 最小主菜单，使 ⌘R / ⌘Q 在显示 Dock 图标时可用
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let refresh = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        appMenu.addItem(refresh)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏 IPPure Bar", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "退出 IPPure Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    // MARK: 刷新

    func refresh() {
        fetchTask?.cancel()
        generation += 1
        let gen = generation
        state.phase = .loading
        render()

        let mode = settings.networkMode
        let client = self.client
        fetchTask = Task { [weak self] in
            do {
                let info = try await client.fetch(mode: mode)
                guard let self, !Task.isCancelled, gen == self.generation else { return }
                self.state.info = info
                self.state.updatedAt = Date()
                self.state.phase = .loaded
                self.render()
                self.dumpIconIfNeeded(info)
            } catch {
                guard let self, !Task.isCancelled, gen == self.generation else { return }
                if (error as? URLError)?.code == .cancelled { return }
                self.state.phase = .failed(error.localizedDescription)
                self.render()
            }
        }
    }

    // MARK: 渲染

    private func render() {
        renderStatusItem()
        renderDock()
    }

    private func renderStatusItem() {
        guard let button = statusItem?.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let plain: [NSAttributedString.Key: Any] = [.font: font]

        switch state.phase {
        case .loading where state.info == nil:
            button.attributedTitle = NSAttributedString(string: "…", attributes: plain)
        case .failed:
            button.attributedTitle = NSAttributedString(string: "⚠\u{FE0E}", attributes: plain)
        case .loading, .loaded:
            guard let info = state.info else { return }
            let s = NSMutableAttributedString(string: info.flag + " ", attributes: plain)
            if let score = info.fraudScore, let level = info.riskLevel {
                s.append(NSAttributedString(string: "\(score)", attributes: [.font: font, .foregroundColor: level.color]))
            } else {
                s.append(NSAttributedString(string: "--", attributes: plain))
            }
            button.attributedTitle = s
        }
    }

    private func renderDock() {
        let iconState: DockIconState
        switch state.phase {
        // 已有数据时，刷新中保持显示旧数据，避免定时刷新时图标闪烁
        case .loading: iconState = state.info.map { .loaded($0) } ?? .loading
        case .failed: iconState = .error
        case .loaded: iconState = state.info.map { .loaded($0) } ?? .loading
        }
        NSApp.applicationIconImage = DockIconRenderer.image(for: iconState)
        if case .failed = state.phase {
            NSApp.dockTile.badgeLabel = "!"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    // MARK: 菜单动作

    @objc func refreshNow() { refresh() }

    @objc func copyIP(_ sender: NSMenuItem) {
        guard let ip = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
    }

    @objc func selectInterval(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        settings.refreshMinutes = minutes
        scheduler.setInterval(minutes: minutes)
    }

    @objc func selectNetworkMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = NetworkMode(rawValue: raw) else { return }
        guard mode != settings.networkMode else { return }
        settings.networkMode = mode
        refresh()
    }

    @objc func toggleShowInDock() {
        settings.showInDock.toggle()
        applyActivationPolicy()
        renderDock()
    }

    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改开机启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc func openWebsite() {
        if let url = URL(string: "https://ippure.com") { NSWorkspace.shared.open(url) }
    }

    // MARK: 调试输出

    private func dumpIconIfNeeded(_ info: IPInfo) {
        guard let path = debug.dumpIconPath else { return }
        debug.dumpIconPath = nil
        if let data = DockIconRenderer.pngData(for: .loaded(info)) {
            do {
                try data.write(to: URL(fileURLWithPath: path))
                print("[debug] dock icon written to \(path)")
            } catch {
                print("[debug] failed to write \(path): \(error)")
            }
        }
        print("[debug] IPInfo: \(info)")
    }

    private func dumpStatesIfNeeded() {
        guard let dir = debug.dumpStatesDir else { return }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func write(_ name: String, _ s: DockIconState) {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if let data = DockIconRenderer.pngData(for: s) { try? data.write(to: url) }
            print("[debug] wrote \(url.path)")
        }
        write("loading.png", .loading)
        write("error.png", .error)
        for score in [5, 35, 60, 90] {
            write("score\(score).png", .loaded(Self.sampleInfo(score: score)))
        }
    }

    nonisolated static func sampleInfo(score: Int) -> IPInfo {
        IPInfo(ip: "103.23.75.11", asn: 2914, asOrganization: "NTT Communications Corporation",
               country: "Japan", countryCode: "JP", region: "Tokyo", regionCode: "13", city: "Tokyo",
               timezone: "Asia/Tokyo", longitude: "139.69171", latitude: "35.6895", postalCode: "101-8656",
               fraudScore: score, isResidential: false, isBroadcast: false)
    }
}
