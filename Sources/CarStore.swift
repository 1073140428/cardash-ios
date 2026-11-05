import SwiftUI

// MARK: - 实体

struct CarItem: Identifiable {
    let id: String
    let name: String
    let unit: String
    let symbol: String
}

let carItems: [CarItem] = [
    CarItem(id: "obd_speed",        name: "车速",       unit: "km/h", symbol: "speedometer"),
    CarItem(id: "obd_rpm",          name: "转速",       unit: "rpm",  symbol: "gauge"),
    CarItem(id: "obd_coolant",      name: "水温",       unit: "°C",   symbol: "thermometer"),
    CarItem(id: "obd_throttle",     name: "节气门",     unit: "%",    symbol: "wind"),
    CarItem(id: "obd_map",          name: "进气压力",   unit: "kPa",  symbol: "arrow.down.circle"),
    CarItem(id: "obd_load",         name: "发动机负荷", unit: "%",    symbol: "chart.bar.fill"),
    CarItem(id: "obd_timing",       name: "点火提前角", unit: "°",    symbol: "bolt.fill"),
    CarItem(id: "obd_voltage",      name: "电瓶电压",   unit: "V",    symbol: "battery.100"),
    CarItem(id: "obd_maf",          name: "空气流量",   unit: "g/s",  symbol: "wind.snow"),
    CarItem(id: "obd_fuel_liters",  name: "油量",       unit: "L",    symbol: "drop.fill")
]

// MARK: - 行程

struct Trip: Identifiable {
    let id: String
    let start: String
    let end: String
    let startTs: Double
    let endTs: Double
    let durationMin: Int
    let distanceKm: Double
    let maxSpeed: Double
    let avgSpeed: Double
    let maxCoolant: Double
    let minVoltage: Double
}

private struct HAPoint: Decodable {
    let state: String
}

private struct HAStateResp: Decodable {
    let state: String
}

// MARK: - 数据层

@MainActor
final class CarStore: ObservableObject {

    @Published var values: [String: String] = [:]
    @Published var connected = false
    @Published var message = ""
    @Published var lastUpdate: Date? = nil

    @Published var trips: [Trip] = []
    @Published var tripsLoading = false
    @Published var tripsError = ""

    private var loop: Task<Void, Never>?

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
        if let st = await fetchState("obd_state") {
            values["obd_state"] = st
            if st == "已连接" { ok += 1 }
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

    // MARK: 行程列表

    func loadTrips() async {
        guard configured else { tripsError = "未配置"; return }
        tripsLoading = true
        tripsError = ""
        defer { tripsLoading = false }

        let df = ISO8601DateFormatter()
        let start = df.string(from: Date().addingTimeInterval(-7 * 24 * 3600))
        let path = base + "/api/history/period/" + start + "?filter_entity_id=sensor.obd_trip"
        guard let url = URL(string: path) else { tripsError = "地址格式不对"; return }

        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                tripsError = "读取失败"
                return
            }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [[[String: Any]]],
                  let rows = root.first else {
                tripsError = "暂无行程"
                return
            }

            var out: [Trip] = []
            var seen = Set<String>()
            for r in rows {
                guard let a = r["attributes"] as? [String: Any] else { continue }
                let st = dbl(a["start_ts"])
                if st <= 0 { continue }
                let key = String(format: "%.0f", st)
                if seen.contains(key) { continue }
                seen.insert(key)

                out.append(Trip(
                    id: key,
                    start: (a["start"] as? String) ?? "--",
                    end: (a["end"] as? String) ?? "--",
                    startTs: st,
                    endTs: dbl(a["end_ts"]),
                    durationMin: Int(dbl(a["duration_min"])),
                    distanceKm: dbl(a["distance_km"]),
                    maxSpeed: dbl(a["max_speed"]),
                    avgSpeed: dbl(a["avg_speed"]),
                    maxCoolant: dbl(a["max_coolant"]),
                    minVoltage: dbl(a["min_voltage"])
                ))
            }

            trips = out.sorted { $0.startTs > $1.startTs }
            if trips.isEmpty { tripsError = "暂无行程（HA 默认只保留 10 天历史）" }
        } catch {
            tripsError = "读取失败"
        }
    }

    /// 某段行程内某个实体的采样值
    func tripSamples(_ trip: Trip, key: String) async -> [Double] {
        let df = ISO8601DateFormatter()
        let s = df.string(from: Date(timeIntervalSince1970: trip.startTs / 1000.0))
        let eDate = Date(timeIntervalSince1970: max(trip.endTs, trip.startTs + 60000) / 1000.0)
        let e = df.string(from: eDate)
        let path = base + "/api/history/period/" + s
            + "?filter_entity_id=sensor." + key
            + "&end_time=" + e
            + "&minimal_response"
        guard let url = URL(string: path) else { return [] }

        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let rows = try JSONDecoder().decode([[HAPoint]].self, from: data)
            return (rows.first ?? []).compactMap { Double($0.state) }
        } catch {
            return []
        }
    }

    private func dbl(_ any: Any?) -> Double {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) ?? 0 }
        return 0
    }

    // MARK: 取值

    func number(_ key: String) -> Double? {
        guard let s = values[key], let d = Double(s) else { return nil }
        return d
    }

    var speed: Double { number("obd_speed") ?? 0 }
    var rpm: Double { number("obd_rpm") ?? 0 }
    var coolant: Double { number("obd_coolant") ?? 0 }
    var throttle: Double { number("obd_throttle") ?? 0 }
    var map: Double { number("obd_map") ?? 0 }
    var load: Double { number("obd_load") ?? 0 }
    var timing: Double { number("obd_timing") ?? 0 }
    var volt: Double { number("obd_voltage") ?? 0 }
    var maf: Double { number("obd_maf") ?? 0 }
    var fuel: Double { number("obd_fuel_liters") ?? 0 }

    var obdState: String { values["obd_state"] ?? "未连接" }
    var driving: Bool { speed > 1 }

    var updatedText: String {
        guard let t = lastUpdate else { return "尚未更新" }
        let s = Int(Date().timeIntervalSince(t))
        if s < 60 { return "更新于 \(max(s, 0)) 秒前" }
        return "更新于 \(s / 60) 分钟前"
    }
}
