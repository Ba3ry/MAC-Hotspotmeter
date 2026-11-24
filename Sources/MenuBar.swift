import AppKit

@MainActor
final class HotspotMenu: NSObject {
    private enum DisplayOption: String, CaseIterable {
        case icon
        case speed
        case usage

        var title: String {
            switch self {
            case .icon: "显示图标"
            case .speed: "显示实时网速"
            case .usage: "显示统计用量"
            }
        }
    }

    private static let displayKey = "statusBarDisplayOptions"
    let menu = NSMenu()
    private let displayMenu = NSMenu()
    private let connection = NSMenuItem()
    private let speed = NSMenuItem()
    private let session = NSMenuItem()
    private let today = NSMenuItem()
    private let month = NSMenuItem()
    private let storageWarning = NSMenuItem(title: "无法保存历史记录", action: nil, keyEquivalent: "")
    private let settings: NSMenuItem
    private let preferences: UserDefaults
    private let hotspotImage = NSImage(systemSymbolName: "personalhotspot", accessibilityDescription: nil)
    private weak var button: NSStatusBarButton?
    private var displayed: Set<DisplayOption>
    private var data = Dashboard()

    init(button: NSStatusBarButton?, target: AnyObject, showHistory: Selector, showSettings: Selector,
         quit: Selector, preferences: UserDefaults = .standard) {
        self.button = button
        self.preferences = preferences
        let saved = Set(preferences.stringArray(forKey: Self.displayKey)?.compactMap(DisplayOption.init(rawValue:)) ?? [])
        displayed = saved.isEmpty ? Set(DisplayOption.allCases) : saved
        settings = NSMenuItem(title: "热点设置…", action: showSettings, keyEquivalent: "")
        let history = NSMenuItem(title: "查看历史记录…", action: showHistory, keyEquivalent: "")
        let exit = NSMenuItem(title: "退出热点流量", action: quit, keyEquivalent: "q")
        super.init()
        menu.autoenablesItems = false
        for entry in [connection, speed, session, today, month, storageWarning] {
            entry.isEnabled = false
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let display = NSMenuItem(title: "状态栏显示", action: nil, keyEquivalent: "")
        displayMenu.autoenablesItems = false
        for option in DisplayOption.allCases {
            let item = NSMenuItem(title: option.title, action: #selector(toggleDisplay(_:)), keyEquivalent: "")
            item.representedObject = option.rawValue
            item.target = self
            displayMenu.addItem(item)
        }
        display.submenu = displayMenu
        menu.addItem(display)
        for action in [history, settings, exit] {
            action.target = target
            menu.addItem(action)
        }
        updateDisplayChoices()
    }

    func update(_ data: Dashboard) {
        self.data = data
        let name = data.hotspot ?? "iPhone 热点"
        connection.title = "\(name) · \(data.linkTitle)"
        let firstSamplePending = data.link == .active && data.rate == nil
        speed.title = fullSpeed ?? (firstSamplePending ? "正在读取网速…" : "")
        speed.isHidden = speed.title.isEmpty
        session.title = "本次连接   " + (data.active.map {
            "\(Format.bytes($0.traffic.total)) · \(Format.duration($0.ended.timeIntervalSince($0.started)))"
        } ?? "—")
        today.title = "今日用量   \(Format.bytes(data.today.total))"
        month.title = "本月用量   \(Format.bytes(data.month.total))"
        storageWarning.isHidden = !data.storageError
        settings.title = data.access == .allowed ? "热点设置…" : "允许识别热点…"
        updateButton()
    }

    @objc private func toggleDisplay(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let option = DisplayOption(rawValue: raw) else { return }
        if displayed.contains(option) {
            guard displayed.count > 1 else { return }
            displayed.remove(option)
        } else {
            displayed.insert(option)
        }
        preferences.set(DisplayOption.allCases.filter { displayed.contains($0) }.map(\.rawValue),
                        forKey: Self.displayKey)
        updateDisplayChoices()
        updateButton()
    }

    private func updateDisplayChoices() {
        for (item, option) in zip(displayMenu.items, DisplayOption.allCases) {
            let checked = displayed.contains(option)
            item.state = checked ? .on : .off
            item.isEnabled = !checked || displayed.count > 1
        }
    }

    private var fullSpeed: String? {
        data.rate.map {
            "下载 \(Format.bytes($0.received))/s    上传 \(Format.bytes($0.sent))/s"
        }
    }

    private func updateButton() {
        guard let button else { return }
        var values: [String] = []
        if displayed.contains(.speed) {
            if let rate = data.rate {
                let down = Format.bytes(rate.received, compact: true)
                let up = Format.bytes(rate.sent, compact: true)
                values.append("↓\(down)/s ↑\(up)/s")
            } else if !displayed.contains(.usage) {
                values.append("↓— ↑—")
            }
        }
        if displayed.contains(.usage) {
            let amount = Format.bytes(data.today.total, compact: true)
            values.append(values.isEmpty ? "今日 \(amount)" : amount)
        }
        let title = values.joined(separator: " · ")
        let image = displayed.contains(.icon) ? hotspotImage : nil
        if button.image !== image { button.image = image }
        button.imagePosition = image == nil ? .noImage : title.isEmpty ? .imageOnly : .imageLeading
        if button.attributedTitle.string != title {
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)]
            )
        }
        var details = ["热点流量", data.linkTitle]
        if displayed.contains(.speed), let fullSpeed { details.append(fullSpeed) }
        if displayed.contains(.usage) { details.append("今日用量 \(Format.bytes(data.today.total))") }
        let description = details.joined(separator: "，")
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }
}
