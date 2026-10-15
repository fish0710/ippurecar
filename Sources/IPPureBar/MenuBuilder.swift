import AppKit

/// 菜单内容。信息区在状态栏菜单与 Dock 菜单中复用。
@MainActor
enum MenuBuilder {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: 信息区

    static func infoItems(state: AppState, mode: NetworkMode, target: AnyObject) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        func row(_ title: String, action: Selector? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            if action != nil { item.target = target }
            return item
        }
        func value(_ s: String?) -> String {
            guard let s, !s.isEmpty else { return "—" }
            return s
        }

        if let info = state.info {
            let ipItem = row("IP：\(value(info.ip))", action: #selector(AppDelegate.copyIP(_:)))
            ipItem.representedObject = info.ip
            ipItem.toolTip = "点击复制"
            items.append(ipItem)
            items.append(row("位置：\(value(info.locationText))"))
            items.append(row("ASN：\(value(info.asnText))"))

            if let score = info.fraudScore, let level = info.riskLevel {
                let item = row("")
                let s = NSMutableAttributedString(string: "风险：")
                s.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: level.color]))
                s.append(NSAttributedString(string: "\(score) · \(level.title)"))
                item.attributedTitle = s
                items.append(item)
            } else {
                items.append(row("风险：—"))
            }

            items.append(row("类型：\(info.broadcastText) IP · \(info.residentialText) IP"))
            items.append(row("时区：\(value(info.timezone))"))
            items.append(row("坐标：\(value(info.coordinateText))"))
            items.append(row("邮编：\(value(info.postalCode))"))
        } else if case .loading = state.phase {
            items.append(row("正在获取…"))
        }

        items.append(row("代理：\(ProxyInfo.description(for: mode))"))

        switch state.phase {
        case .loading:
            if let t = state.updatedAt { items.append(row("上次更新：\(timeFormatter.string(from: t))")) }
        case .loaded:
            if let t = state.updatedAt { items.append(row("更新时间：\(timeFormatter.string(from: t))")) }
        case .failed(let message):
            let item = row("")
            item.attributedTitle = NSAttributedString(
                string: "错误：\(message)", attributes: [.foregroundColor: NSColor.systemRed])
            items.append(item)
            if let t = state.updatedAt { items.append(row("上次成功：\(timeFormatter.string(from: t))")) }
        }
        return items
    }

    // MARK: 状态栏菜单

    static func fill(statusMenu menu: NSMenu, state: AppState, settings: Settings,
                     launchAtLogin: Bool, target: AppDelegate) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        for item in infoItems(state: state, mode: settings.networkMode, target: target) { menu.addItem(item) }
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "立即刷新", action: #selector(AppDelegate.refreshNow), keyEquivalent: "r")
        refresh.target = target
        menu.addItem(refresh)

        // 自动刷新
        let autoItem = NSMenuItem(title: "自动刷新", action: nil, keyEquivalent: "")
        let autoMenu = NSMenu(title: "自动刷新")
        autoMenu.autoenablesItems = false
        for minutes in Settings.refreshChoices {
            let title = minutes == 0 ? "关闭" : "\(minutes) 分钟"
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.selectInterval(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = minutes
            item.state = settings.refreshMinutes == minutes ? .on : .off
            autoMenu.addItem(item)
        }
        autoItem.submenu = autoMenu
        menu.addItem(autoItem)

        // 网络模式
        let netItem = NSMenuItem(title: "网络模式", action: nil, keyEquivalent: "")
        let netMenu = NSMenu(title: "网络模式")
        netMenu.autoenablesItems = false
        for (mode, title) in [(NetworkMode.system, "跟随系统代理"), (NetworkMode.direct, "直连")] {
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.selectNetworkMode(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = mode.rawValue
            item.state = settings.networkMode == mode ? .on : .off
            netMenu.addItem(item)
        }
        netItem.submenu = netMenu
        menu.addItem(netItem)

        let dock = NSMenuItem(title: "在 Dock 中显示", action: #selector(AppDelegate.toggleShowInDock), keyEquivalent: "")
        dock.target = target
        dock.state = settings.showInDock ? .on : .off
        menu.addItem(dock)

        let login = NSMenuItem(title: "开机启动", action: #selector(AppDelegate.toggleLaunchAtLogin), keyEquivalent: "")
        login.target = target
        login.state = launchAtLogin ? .on : .off
        menu.addItem(login)

        let web = NSMenuItem(title: "在 IPPure 网页查看", action: #selector(AppDelegate.openWebsite), keyEquivalent: "")
        web.target = target
        menu.addItem(web)

        let log = NSMenuItem(title: "查看刷新日志", action: #selector(AppDelegate.openRefreshLog), keyEquivalent: "")
        log.target = target
        menu.addItem(log)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: Dock 菜单

    static func dockMenu(state: AppState, settings: Settings, target: AppDelegate) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in infoItems(state: state, mode: settings.networkMode, target: target) { menu.addItem(item) }
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "立即刷新", action: #selector(AppDelegate.refreshNow), keyEquivalent: "")
        refresh.target = target
        menu.addItem(refresh)
        let web = NSMenuItem(title: "在 IPPure 网页查看", action: #selector(AppDelegate.openWebsite), keyEquivalent: "")
        web.target = target
        menu.addItem(web)
        return menu
    }
}
