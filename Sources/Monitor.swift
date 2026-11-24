import AppKit
import Combine
import CoreLocation
import CoreWLAN
import Foundation

enum Access: Equatable {
    case ask
    case off
    case allowed
}

enum LinkState: Equatable {
    case unconfigured
    case waiting
    case unavailable
    case active
}

struct DailyUsage: Identifiable {
    var date: Date
    var traffic: Traffic
    var id: Date { date }
}

struct Dashboard {
    var access = Access.ask
    var hotspot: String?
    var network: String?
    var link = LinkState.unconfigured
    var rate: Traffic?
    var active: Session?
    var today = Traffic()
    var month = Traffic()
    var days: [DailyUsage] = []
    var sessions: [Session] = []
    var storageError = false

    var linkTitle: String {
        if access != .allowed { return "待授权" }
        switch link {
        case .unconfigured: return "待设置"
        case .waiting: return "热点未连接"
        case .unavailable: return "读取中断"
        case .active: return "统计中"
        }
    }
}

@MainActor
final class Monitor: NSObject, ObservableObject {
    @Published private(set) var dashboard = Dashboard()
    var updateMenu: ((Dashboard) -> Void)?

    private let wifi = CWWiFiClient.shared()
    private let location = CLLocationManager()
    private let store: HistoryStore?
    private let days = LocalDays()
    private var meter = Meter()
    private var hotspot = UserDefaults.standard.string(forKey: "hotspotName")
        ?? UserDefaults(suiteName: "local.codex.hotspot-meter")?.string(forKey: "hotspotName")
    private var timer: Timer?
    private var sleeping = false
    private var lastSavedRevision = 0
    private var lastSaveUptime: TimeInterval = 0
    private var storageError = false
    private var canWriteHistory = true

    override init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        store = directory.map {
            HistoryStore(file: $0.appendingPathComponent("HotspotMeter/history.json"))
        }
        super.init()
        do {
            if let store { meter.history = try store.load() }
        } catch {
            storageError = true
            canWriteHistory = false
        }
        storageError = storageError || store == nil
    }

    func start() {
        location.delegate = self
        wifi.delegate = self
        // Polling also detects changes on systems that do not deliver CoreWLAN events.
        try? wifi.startMonitoringEvent(with: .ssidDidChange)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        let timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        meter.disconnect()
        persist(force: true)
    }

    func requestAccess() {
        guard access == .ask else { return }
        location.requestWhenInUseAuthorization()
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    func selectCurrentNetwork(_ expected: String) -> Bool {
        guard access == .allowed, let name = wifi.interface()?.ssid(), sameName(name, expected) else {
            tick()
            return false
        }
        meter.disconnect()
        hotspot = name
        UserDefaults.standard.set(name, forKey: "hotspotName")
        tick()
        return true
    }

    private var access: Access {
        switch location.authorizationStatus {
        case .notDetermined: .ask
        case .authorizedAlways, .authorizedWhenInUse: .allowed
        case .restricted, .denied: .off
        @unknown default: .off
        }
    }

    private func sameName(_ left: String, _ right: String) -> Bool {
        left.utf8.elementsEqual(right.utf8)
    }

    @objc private func willSleep() {
        sleeping = true
        tick()
    }

    @objc private func didWake() {
        sleeping = false
        tick()
    }

    @objc private func tick() {
        let permission = access
        let interface = !sleeping && permission == .allowed ? wifi.interface() : nil
        var network = interface?.ssid()
        var reading: Reading?
        var state = LinkState.unconfigured

        if let hotspot {
            if let current = network, sameName(hotspot, current), let interface,
               let name = interface.interfaceName, let counters = InterfaceTraffic.read(name),
               let confirmed = interface.ssid(), sameName(confirmed, hotspot) {
                reading = Reading(interface: name, counters: counters, time: Date(),
                                  uptime: ProcessInfo.processInfo.systemUptime)
                state = .active
            } else {
                // Re-read after a potential link transition so the panel reports the latest network.
                network = interface?.ssid()
                if permission != .allowed {
                    state = .waiting
                } else if let network, sameName(hotspot, network) {
                    state = .unavailable
                } else {
                    state = .waiting
                }
            }
        }

        let previouslyActive = meter.current != nil
        meter.sample(reading, using: days)
        persist(force: previouslyActive && meter.current == nil)

        let now = Date()
        let calendar = days.calendar
        let today = calendar.startOfDay(for: now)
        let week = (-6...0).compactMap { offset -> DailyUsage? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return DailyUsage(date: date, traffic: meter.history.daily[days.key(for: date)] ?? Traffic())
        }
        dashboard = Dashboard(
            access: permission, hotspot: hotspot, network: network, link: state, rate: meter.rate,
            active: meter.current, today: meter.history.daily[days.key(for: now)] ?? Traffic(),
            month: days.monthTotal(at: now, in: meter.history), days: week,
            sessions: Array(meter.history.sessions.prefix(100)), storageError: storageError
        )
        updateMenu?(dashboard)
    }

    private func persist(force: Bool) {
        guard let store, canWriteHistory, lastSavedRevision != meter.revision else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime
        guard force || elapsed - lastSaveUptime >= 5 else { return }
        lastSaveUptime = elapsed
        do {
            try store.save(meter.persistedHistory())
            lastSavedRevision = meter.revision
            storageError = false
        } catch {
            storageError = true
        }
    }
}

extension Monitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.tick() }
    }
}

extension Monitor: CWEventDelegate {
    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            guard let self, wifi.interface()?.interfaceName == interfaceName else { return }
            meter.disconnect()
            persist(force: true)
            tick()
        }
    }
}
