import AppKit
import SwiftUI

enum Format {
    static func bytes(_ value: UInt64, compact: Bool = false) -> String {
        let count = Double(value)
        if count < 1_000 { return compact ? "\(value)B" : "\(value) B" }
        if count < 1_000_000 { return unit(count / 1_000, "KB", compact: compact) }
        if count < 1_000_000_000 { return unit(count / 1_000_000, "MB", compact: compact) }
        if count < 1_000_000_000_000 { return unit(count / 1_000_000_000, "GB", compact: compact) }
        return unit(count / 1_000_000_000_000, "TB", compact: compact)
    }

    private static func unit(_ value: Double, _ name: String, compact: Bool) -> String {
        let decimals = value < 10 && !compact ? 2 : value < 100 ? 1 : 0
        let space = compact ? "" : " "
        return "\(value.formatted(.number.precision(.fractionLength(0...decimals))))\(space)\(name)"
    }

    static func duration(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time))
        if seconds < 60 { return "\(seconds) 秒" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分"
    }

    static func date(_ date: Date, time: Bool = false) -> String {
        let format = Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "zh_CN"))
            .month(.defaultDigits).day()
        return date.formatted(time ? format.hour().minute() : format)
    }
}

struct DashboardView: View {
    let data: Dashboard
    var allow: () -> Void = {}
    var pin: (String) -> Bool = { _ in true }
    var quit: () -> Void = {}
    @State private var tab: Tab
    @State private var choosing: Bool
    @State private var changedDuringSelection = false
    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.33, green: 0.86, blue: 0.82)
            : Color(red: 0.03, green: 0.39, blue: 0.38)
    }

    private enum Tab: String, CaseIterable {
        case overview = "概览"
        case history = "历史"
    }

    init(data: Dashboard, allow: @escaping () -> Void = {}, pin: @escaping (String) -> Bool = { _ in true },
         quit: @escaping () -> Void = {}, initialHistory: Bool = false, initiallyChoosing: Bool = false) {
        self.data = data
        self.allow = allow
        self.pin = pin
        self.quit = quit
        self._tab = State(initialValue: initialHistory ? .history : .overview)
        self._choosing = State(initialValue: initiallyChoosing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Picker("页面", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == .overview {
                overview
            } else {
                history
            }

            if data.storageError {
                Label("无法保存历史记录", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            Divider()
            footer
        }
        .padding(18)
        .frame(width: 406)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "personalhotspot")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("热点流量").font(.system(size: 20, weight: .semibold))
                Text(data.hotspot ?? "iPhone 热点")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(data.linkTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(data.link == .active ? accent : Color.secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background((data.link == .active ? accent : Color.secondary).opacity(0.12), in: Capsule())
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if data.access != .allowed || data.hotspot == nil || choosing {
                setup
            } else if data.link == .unavailable {
                Label("暂时读不到网络流量，应用会自动重试。", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                speed("实时下载", "arrow.down", data.rate?.received)
                speed("实时上传", "arrow.up", data.rate?.sent)
            }

            VStack(spacing: 0) {
                total("本次连接", value: data.active.map { Format.bytes($0.traffic.total) } ?? "—",
                      detail: data.active.map { Format.duration($0.ended.timeIntervalSince($0.started)) })
                Divider().padding(.leading, 12)
                total("今天", value: Format.bytes(data.today.total), detail: nil)
                Divider().padding(.leading, 12)
                total("本月", value: Format.bytes(data.month.total), detail: nil)
            }
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 8) {
            if data.access == .ask {
                Text("授权后，应用才能读取 Wi-Fi 名称并识别 iPhone 热点。")
                    .font(.subheadline)
                Button("允许识别热点", action: allow)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            } else if data.access == .off {
                Text("请在系统设置的「定位服务」中允许「热点流量」读取 Wi-Fi 名称。")
                    .font(.subheadline)
                Button("打开定位服务设置", action: allow)
            } else {
                Text("先在 Mac 的 Wi-Fi 菜单里连上 iPhone 热点，再确认下方网络。")
                    .font(.subheadline)
                if let network = data.network {
                    Text(network).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Button("将此 Wi-Fi 设为热点") {
                        let saved = pin(network)
                        changedDuringSelection = !saved
                        if saved { choosing = false }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                } else {
                    Text("暂未读取到 Wi-Fi 名称").font(.caption).foregroundStyle(.secondary)
                }
                if changedDuringSelection {
                    Text("Wi-Fi 已切换，请重新确认。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func speed(_ title: String, _ symbol: String, _ value: UInt64?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value.map { Format.bytes($0) + "/s" } ?? "—")
                .font(.system(size: 21, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func total(_ title: String, value: String, detail: String?) -> some View {
        HStack(spacing: 9) {
            Text(title).font(.subheadline)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var history: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("最近 7 天").font(.headline)
                    let peak = Double(data.days.map(\.traffic.total).max() ?? 0)
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(data.days) { day in
                            let value = day.traffic.total
                            let height = peak > 0 ? 53 * Double(value) / peak : 0
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(value == 0 ? Color.secondary.opacity(0.22) : accent)
                                    .frame(height: max(3, height))
                                    .frame(height: 53, alignment: .bottom)
                                Text(Format.date(day.date))
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .help(Format.date(day.date) + " · " + Format.bytes(value))
                            .accessibilityLabel(Format.date(day.date) + "，" + Format.bytes(value))
                        }
                    }
                    if peak == 0 {
                        Text("这 7 天暂无已记录的热点流量。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))

                Text("连接记录").font(.headline)
                if data.sessions.isEmpty {
                    Text("热点断开后，本次用量会出现在这里。")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(data.sessions) { session in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(Format.date(session.started, time: true)).font(.subheadline.weight(.medium))
                                    Text(Format.duration(session.ended.timeIntervalSince(session.started)))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 6)
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(Format.bytes(session.traffic.total))
                                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                                    Text("↓ \(Format.bytes(session.traffic.received))  ↑ \(Format.bytes(session.traffic.sent))")
                                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 7)
                            .accessibilityElement(children: .combine)
                            Divider()
                        }
                    }
                }
            }
            .padding(.trailing, 4)
        }
        .frame(height: 270)
    }

    private var footer: some View {
        HStack {
            if data.hotspot != nil, data.access == .allowed, tab == .overview {
                Button(choosing ? "取消更换" : "更换热点") {
                    changedDuringSelection = false
                    choosing.toggle()
                }
            } else {
                Label("记录保存在此 Mac", systemImage: "internaldrive")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("退出", action: quit)
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}
