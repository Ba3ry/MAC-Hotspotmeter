import Foundation

struct Traffic: Codable, Equatable {
    var received: UInt64 = 0
    var sent: UInt64 = 0

    var total: UInt64 { received + sent }

    static func + (left: Self, right: Self) -> Self {
        Self(received: left.received + right.received, sent: left.sent + right.sent)
    }

    func increase(from previous: Self) -> Self? {
        guard received >= previous.received, sent >= previous.sent else { return nil }
        return Self(received: received - previous.received, sent: sent - previous.sent)
    }
}

struct Session: Codable, Identifiable {
    var id = UUID()
    var started: Date
    var ended: Date
    var traffic = Traffic()
}

struct History: Codable {
    var daily: [String: Traffic] = [:]
    var sessions: [Session] = []

    mutating func close(_ session: Session) {
        guard session.ended > session.started else { return }
        sessions.insert(session, at: 0)
        if sessions.count > 100 {
            sessions.removeLast(sessions.count - 100)
        }
    }
}

struct Reading {
    var interface: String
    var counters: Traffic
    var time: Date
    var uptime: TimeInterval
}

struct Meter {
    var history = History()
    private(set) var current: Session?
    private(set) var rate: Traffic?
    private(set) var revision = 0
    private var last: Reading?

    mutating func sample(_ reading: Reading?, using days: LocalDays) {
        guard let reading else {
            disconnect()
            return
        }

        guard let previous = last, var session = current else {
            begin(at: reading)
            return
        }

        let elapsed = reading.uptime - previous.uptime
        if (0..<0.05).contains(elapsed), reading.interface == previous.interface {
            return
        }
        guard reading.interface == previous.interface, (0.05...5).contains(elapsed),
              let increase = reading.counters.increase(from: previous.counters) else {
            disconnect()
            begin(at: reading)
            return
        }

        rate = Traffic(
            received: UInt64((Double(increase.received) / elapsed).rounded()),
            sent: UInt64((Double(increase.sent) / elapsed).rounded())
        )
        session.traffic = session.traffic + increase
        session.ended = max(session.ended, reading.time)
        current = session
        add(increase, from: previous.time, to: reading.time, using: days)
        last = reading
        revision += 1
    }

    mutating func disconnect() {
        if let current {
            history.close(current)
            revision += 1
        }
        current = nil
        rate = nil
        last = nil
    }

    func persistedHistory() -> History {
        var snapshot = history
        if let current { snapshot.close(current) }
        return snapshot
    }

    private mutating func begin(at reading: Reading) {
        last = reading
        current = Session(started: reading.time, ended: reading.time)
    }

    private mutating func add(_ traffic: Traffic, from start: Date, to end: Date, using days: LocalDays) {
        let endKey = days.key(for: end)
        let startKey = days.key(for: start)
        let boundary = days.calendar.startOfDay(for: end)
        if end > start, end.timeIntervalSince(start) <= 5, startKey != endKey,
           boundary >= start, boundary <= end {
            let fraction = boundary.timeIntervalSince(start) / end.timeIntervalSince(start)
            let before = Traffic(
                received: UInt64((Double(traffic.received) * fraction).rounded(.down)),
                sent: UInt64((Double(traffic.sent) * fraction).rounded(.down))
            )
            history.daily[startKey, default: Traffic()] = history.daily[startKey, default: Traffic()] + before
            let remaining = traffic.increase(from: before) ?? Traffic()
            history.daily[endKey, default: Traffic()] = history.daily[endKey, default: Traffic()] + remaining
            return
        }
        history.daily[endKey, default: Traffic()] = history.daily[endKey, default: Traffic()] + traffic
    }
}

struct LocalDays {
    var calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .autoupdatingCurrent
        return value
    }()

    func key(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    func monthTotal(at date: Date, in history: History) -> Traffic {
        let prefix = key(for: date).prefix(7)
        return history.daily.reduce(into: Traffic()) { total, entry in
            if entry.key.hasPrefix(prefix) { total = total + entry.value }
        }
    }
}

struct HistoryStore {
    var file: URL

    func load() throws -> History {
        do {
            return try JSONDecoder().decode(History.self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return History()
        }
    }

    func save(_ history: History) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(history).write(to: file, options: .atomic)
    }
}
