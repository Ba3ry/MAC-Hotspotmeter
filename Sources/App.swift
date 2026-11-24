import AppKit
import SwiftUI

struct LiveDashboard: View {
    @ObservedObject var monitor: Monitor
    var history: Bool
    var authorize: () -> Void

    var body: some View {
        DashboardView(data: monitor.dashboard, allow: authorize,
                      pin: monitor.selectCurrentNetwork, quit: { NSApp.terminate(nil) },
                      initialHistory: history, initiallyChoosing: !history && monitor.dashboard.hotspot != nil)
            .frame(minHeight: 480, alignment: .top)
    }
}

struct AuthorizationView: View {
    @ObservedObject var monitor: Monitor
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("识别 iPhone 热点").font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if monitor.dashboard.access != .allowed {
                    Button("打开定位服务设置", action: monitor.openLocationSettings)
                }
                Spacer()
                if monitor.dashboard.access == .ask {
                    Button("请求授权", action: monitor.requestAccess)
                        .keyboardShortcut(.defaultAction)
                } else if monitor.dashboard.access == .allowed {
                    Button("返回菜单栏", action: close)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 430)
        .frame(minHeight: 158)
    }

    private var message: String {
        switch monitor.dashboard.access {
        case .ask:
            "点「请求授权」，再在 macOS 弹窗里点「允许」。定位权限仅用于读取当前 Wi-Fi 名称。"
        case .off:
            "请打开「定位服务」，确认总开关已开启，并允许列表中的「热点流量」。"
        case .allowed:
            "已授权。连上 iPhone 热点后，从菜单栏选择「热点设置…」。"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let monitor = Monitor()
    private var statusItem: NSStatusItem?
    private var statusMenu: HotspotMenu?
    private var authorizationWindow: NSWindow?
    private var dashboardWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "HotspotMeter"
        let statusMenu = HotspotMenu(button: item.button, target: self, showHistory: #selector(showHistory),
                                     showSettings: #selector(showSettings), quit: #selector(quit))
        item.menu = statusMenu.menu
        statusItem = item
        self.statusMenu = statusMenu
        monitor.updateMenu = { [weak statusMenu] data in
            statusMenu?.update(data)
        }
        monitor.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if monitor.dashboard.access != .allowed {
                showAuthorizationWindow()
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            if monitor.dashboard.access == .allowed, monitor.dashboard.hotspot != nil {
                showHistory()
            } else {
                showSettings()
            }
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === authorizationWindow { authorizationWindow = nil }
        if window === dashboardWindow { dashboardWindow = nil }
        if authorizationWindow == nil, dashboardWindow == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func showAuthorizationWindow() {
        if authorizationWindow == nil {
            let controller = NSHostingController(rootView: AuthorizationView(monitor: monitor) { [weak self] in
                self?.authorizationWindow?.close()
            })
            let window = NSWindow(contentViewController: controller)
            window.title = "热点流量 · 授权"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            authorizationWindow = window
        }
        activate(authorizationWindow)
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    @objc private func showSettings() {
        if monitor.dashboard.access == .allowed {
            showDashboard(history: false)
        } else {
            showAuthorizationWindow()
        }
    }

    @objc private func showHistory() {
        showDashboard(history: true)
    }

    private func showDashboard(history: Bool) {
        let controller = NSHostingController(rootView: LiveDashboard(monitor: monitor, history: history) { [weak self] in
            self?.showAuthorizationWindow()
        })
        if let window = dashboardWindow {
            window.contentViewController = controller
        } else {
            let window = NSWindow(contentViewController: controller)
            window.title = "热点流量"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            dashboardWindow = window
        }
        activate(dashboardWindow)
    }

    private func activate(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@main
struct HotspotMeterApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
