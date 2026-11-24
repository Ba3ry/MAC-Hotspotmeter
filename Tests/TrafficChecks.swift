import Foundation

@main
struct TrafficChecks {
    static func main() throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 28_800)!
        let days = LocalDays(calendar: calendar)
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 59, second: 59))!
        let base: UInt64 = 9_000_000_000
        func reading(_ offset: TimeInterval, down: UInt64, up: UInt64, interface: String = "en0") -> Reading {
            Reading(interface: interface, counters: Traffic(received: down, sent: up),
                    time: start.addingTimeInterval(offset), uptime: 100 + offset)
        }
        var meter = Meter()
        meter.sample(reading(0, down: base, up: base), using: days)
        precondition(meter.rate == nil && meter.current?.traffic.total == 0)
        meter.sample(reading(2, down: base + 5500, up: base + 900), using: days)
        precondition(meter.rate == Traffic(received: 2750, sent: 450))
        precondition(meter.history.daily["2026-10-31"] == Traffic(received: 2750, sent: 450))
        precondition(days.monthTotal(at: start.addingTimeInterval(2), in: meter.history).total == 3200)
        precondition(meter.current?.traffic.total == 6400)

        let store = HistoryStore(file: dir.appendingPathComponent("verification-history.json"))
        try store.save(meter.persistedHistory())
        let restored = try store.load()
        precondition(restored.daily == meter.history.daily && restored.sessions.first?.traffic.total == 6400)
        meter.sample(nil, using: days)
        precondition(meter.current == nil && meter.history.sessions.count == 1)
        meter.sample(reading(3, down: base + 750_000, up: base + 250_000), using: days)
        precondition(meter.current?.traffic.total == 0)
        meter.sample(reading(4, down: base + 750_001, up: base + 250_049), using: days)
        precondition(meter.current?.traffic.total == 50)
        meter.sample(reading(12, down: base + 900_000, up: base + 900_000), using: days)
        precondition(meter.current?.traffic.total == 0, "gap must not credit counters")
        meter.sample(reading(13, down: 15, up: 25), using: days)
        precondition(meter.current?.traffic.total == 0, "counter reset must not credit counters")
        meter.sample(reading(14, down: 17, up: 26, interface: "en1"), using: days)
        precondition(meter.current?.traffic.total == 0, "new interface must establish its own baseline")
        precondition(days.monthTotal(at: start.addingTimeInterval(14), in: meter.history).total == 3250)
        print("Passed 64-bit deltas, midnight and month boundaries, disconnect/reconnect, sleep gap, reset, interface change, and persistence")
    }
}
