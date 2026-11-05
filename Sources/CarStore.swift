import SwiftUI

// MARK: - 实体定义

struct CarItem: Identifiable {
    let id: String
    let name: String
    let unit: String
    let symbol: String
}

let carItems: [CarItem] = [
    CarItem(id: "car_speed",      name: "车速",   unit: "km/h", symbol: "speedometer"),
    CarItem(id: "car_rpm",        name: "转速",   unit: "RPM",  symbol: "gauge"),
    CarItem(id: "car_fuel",       name: "油量",   unit: "L",    symbol: "drop.fill"),
    CarItem(id: "car_voltage",    name: "电压",   unit: "V",    symbol: "bolt.fill"),
    CarItem(id: "car_water_temp", name: "水温",   unit: "°C",   symbol: "thermometer"),
    CarItem(id: "car_odometer",   name: "总里程", unit: "km",   symbol: "map")
]

// MARK: - HA 历史点

private struct HAPoint: Decodable {
    let state: String
}

private struct HAStateResp: Decodable {
    let state: String
    let lastChanged: String?

    enum CodingKeys: String, CodingKey {
        case state
        case lastChanged = "last_changed"
    }
}

// MARK: - 数据层

@MainActor
final class CarStore: ObservableObject {

    @Published var values: [String: String] = [:]
    @Published var connected = false
    @Published var message = ""
    @Published var lastUpdate: Date? = nil

    // 行程
    @Published var speedHistory: [Double] = []
    @Published var odoHistory: [Double] = []
    @Published var historyLoading = false
    @Published var historyError = ""

    private var loop: Task<Void, Never>?
    private var lastHistoryLoad: Date? = nil

    var base: String {
        (UserDefaults.standard.string(forKey: "base") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var token: String {
        (UserDefaults.standard.string(forKey: "token") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var configured: Bool { !base.isEmpty && !token.isEmpty }

    // MARK: 轮询

    func start() {
        stop()
        loop = Task { @MainActor in
            while !Task.isCancelled {
                await refresh()
                let driving = (Double(values["car_speed"] ?? "") ?? 0) > 0
                let interval: UInt64 = driving ? 2_000_000_000 : 8_000_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func refresh() async {
        guard configured else {
            message = "请到「设置」填写 HA 地址和令牌"
            connected = false
            return
        }

        var ok = 0
        for item in carItems {
            if let v = await fetchState(item.id) {
                values[item.id] = v
                ok += 1
            }
        }

        connected = ok > 0
        if ok == 0 {
            message = "连不上服务器"
        } else {
            message = ""
            lastUpdate = Date()
        }
    }

    private func fetchState(_ key: String) async -> String? {
        guard let url = URL(string: base + "/api/states/sensor." + key) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(HAStateResp.self, from: data).state
        } catch {
            return nil
        }
    }

    // MARK: 历史（行程用）

    func loadHistory(force: Bool = false) async {
        guard configured else {
            historyError = "未配置"
            return
        }
        if !force, let t = lastHistoryLoad, Date().timeIntervalSince(t) < 60 { return }

        historyLoading = true
        historyError = ""
        defer { historyLoading = false }

        let df = ISO8601DateFormatter()
        let start = df.string(from: Date().addingTimeInterval(-6 * 3600))

        speedHistory = await historyValues(entity: "sensor.car_speed", start: start).compactMap { Double($0) }
        odoHistory = await historyValues(entity: "sensor.car_odometer", start: start).compactMap { Double($0) }

        if speedHistory.isEmpty && odoHistory.isEmpty {
            historyError = "这段时间没有历史数据"
        }
        lastHistoryLoad = Date()
    }

    private func historyValues(entity: String, start: String) async -> [String] {
        let path = base + "/api/history/period/" + start
            + "?filter_entity_id=" + entity + "&minimal_response"
        guard let url = URL(string: path) else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let rows = try JSONDecoder().decode([[HAPoint]].self, from: data)
            return (rows.first ?? []).map { $0.state }
        } catch {
            return []
        }
    }

    // MARK: 便捷取值

    func number(_ key: String) -> Double? {
        guard let s = values[key], let d = Double(s) else { return nil }
        return d
    }

    var speed: Double { number("car_speed") ?? 0 }
    var rpm: Double { number("car_rpm") ?? 0 }
    var fuel: Double { number("car_fuel") ?? 0 }
    var volt: Double { number("car_voltage") ?? 0 }
    var water: Double { number("car_water_temp") ?? 0 }
    var odo: Double { number("car_odometer") ?? 0 }

    var driving: Bool { speed > 1 }

    var updatedText: String {
        guard let t = lastUpdate else { return "尚未更新" }
        let s = Int(Date().timeIntervalSince(t))
        if s < 60 { return "更新于 \(max(s, 0)) 秒前" }
        return "更新于 \(s / 60) 分钟前"
    }

    // 行程统计
    var tripAvgSpeed: Double? {
        let v = speedHistory.filter { $0 > 0 }
        guard !v.isEmpty else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }

    var tripMaxSpeed: Double? { speedHistory.max() }

    var tripDistance: Double? {
        guard let a = odoHistory.first, let b = odoHistory.last, b >= a else { return nil }
        return b - a
    }
}
