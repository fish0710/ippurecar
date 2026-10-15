import AppKit
import Network
import SystemConfiguration

/// 定时 + 网络变化 + 系统代理变化 + 唤醒 触发刷新。事件触发均去抖 2 秒。
@MainActor
final class RefreshScheduler {
    var onTrigger: ((RefreshTrigger) -> Void)?

    private var timer: Timer?
    private var debounceTask: Task<Void, Never>?
    private let monitor = NWPathMonitor()
    private var lastPathSignature: String?
    private var dynamicStore: SCDynamicStore?
    private var wakeObserver: NSObjectProtocol?

    func start(intervalMinutes: Int) {
        setInterval(minutes: intervalMinutes)
        startPathMonitor()
        startProxyWatcher()
        startWakeObserver()
    }

    /// 0 表示关闭定时刷新
    func setInterval(minutes: Int) {
        timer?.invalidate()
        timer = nil
        guard minutes > 0 else { return }
        let t = Timer(timeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTrigger?(.timer) }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 去抖 2 秒后触发
    func scheduleDebounced(_ trigger: RefreshTrigger) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.onTrigger?(trigger)
        }
    }

    // MARK: 网络变化

    private func startPathMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            let sig = "\(path.status)-" + path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
            Task { @MainActor in
                guard let self else { return }
                defer { self.lastPathSignature = sig }
                // 首次回调只记录，不触发
                guard let last = self.lastPathSignature, last != sig, path.status == .satisfied else { return }
                self.scheduleDebounced(.network)
            }
        }
        monitor.start(queue: DispatchQueue(label: "ippurebar.pathmonitor"))
    }

    // MARK: 系统代理变化

    private func startProxyWatcher() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            let scheduler = Unmanaged<RefreshScheduler>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in scheduler.scheduleDebounced(.proxy) }
        }
        guard let store = SCDynamicStoreCreate(nil, "IPPureBar" as CFString, callback, &context) else { return }
        SCDynamicStoreSetNotificationKeys(store, ["State:/Network/Global/Proxies"] as CFArray, nil)
        if let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        dynamicStore = store
    }

    // MARK: 唤醒

    private func startWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleDebounced(.wake) }
        }
    }
}
