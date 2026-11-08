import SwiftUI
import CoreLocation

// MARK: - 数据项

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
    CarItem(id: "obd_fuel_liters",  name: "油量",       unit: "L",    symbol: "drop.fill"),
    CarItem(id: "obd_odometer",     name: "总里程",     unit: "km",   symbol: "map")
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
    let file: String
}

struct TireInfo: Identifiable, Codable {
    let slot: Int
    let name: String
    let kpa: Double
    let tempC: Double
    let battery: Double
    let alarm: String
    var id: Int { slot }
    var ok: Bool { alarm.isEmpty || alarm == "正常" }
    var bar: Double { kpa / 100.0 }
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

    @Published var tires: [TireInfo] = []
    @Published var tiresStale = false          // true = 当前显示的是上次缓存的数据
    @Published var tiresCachedAt: Date? = nil  // 缓存时间
    @Published var trips: [Trip] = []
    @Published var tripsLoading = false
    @Published var tripsError = ""

    // 定位
    @Published var lat: Double = 0
    @Published var lon: Double = 0
    @Published var locAddress: String = ""
    @Published var locStatus: String = ""
    private var lastGeocode: Date? = nil
    private var geocoderBusy = false

    private var loop: Task<Void, Never>?
    private var lastErr = ""
    private var reachable = false

    var base: String {
        var s = (UserDefaults.standard.string(forKey: "base") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        let low = s.lowercased()
        if !low.hasPrefix("http://") && !low.hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    var token: String {
        (UserDefaults.standard.string(forKey: "token") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var configured: Bool { !base.isEmpty && !token.isEmpty }

    // MARK: 轮询

    func start() {
        restoreTireCacheIfNeeded()
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
            message = "请到「设置」填写服务地址和令牌"
            connected = false
            return
        }
        guard let url = URL(string: base + "/api/live") else {
            lastErr = "地址格式不对：" + base
            message = lastErr
            connected = false
            return
        }
        lastErr = ""
        do {
            let (data, http) = try await Net.get(url, token: token)
            if http.statusCode == 401 {
                lastErr = "令牌不对，请到网页「设备」页重新复制"
                message = lastErr
                connected = false
                return
            }
            guard http.statusCode == 200 else {
                lastErr = "服务返回 " + String(http.statusCode)
                message = lastErr
                connected = false
                return
            }
            guard let d = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            reachable = true
            connected = true
            applyLive(d)
            lastUpdate = Date()
            message = values["obd_speed"] == nil
                ? "服务已连上，但还没有车辆数据（车机未上报）"
                : ""
        } catch {
            connected = false
            reachable = false
            lastErr = error.localizedDescription
            message = "连不上服务：" + lastErr
        }
    }

    /// 把 /api/live 的返回填进 values（沿用旧键名，界面不用改）
    private func applyLive(_ d: [String: Any]) {
        func put(_ key: String, _ v: Any?) {
            guard let v = v, !(v is NSNull) else { return }
            if let n = v as? NSNumber {
                values[key] = Self.fmt(n.doubleValue)
            } else if let s = v as? String, !s.isEmpty, s != "None" {
                values[key] = s
            }
        }
        put("obd_rpm", d["rpm"])
        put("obd_speed", d["speed"])
        put("obd_coolant", d["coolant"])
        put("obd_voltage", d["voltage"])
        put("obd_fuel_liters", d["fuel"])
        put("obd_odometer", d["odo"])
        values["obd_state"] = (d["online"] as? Bool ?? false) ? "已连接" : "离线"

        // 今日里程 / 上次加油
        if let today = d["today"] as? [String: Any] {
            let km = Self.dbl(today["distance_km"])
            let n = Int(Self.dbl(today["trips"]))
            values["today_km"] = n > 0 ? String(format: "%.1f", km) : "0"
        } else {
            values["today_km"] = "--"
        }
        if let rf = d["refuel"] as? [String: Any], Self.dbl(rf["odo"]) > 0 {
            let since = Self.dbl(rf["since_km"])
            values["refuel_km"] = String(format: "%.1f", since)
            values["refuel_odo"] = String(format: "%.0f", Self.dbl(rf["odo"]))
        } else {
            values["refuel_km"] = "--"
            values["refuel_odo"] = "--"
        }

        // 故障码
        if let dtc = d["dtc"] as? [String: Any], let codes = dtc["codes"] as? [[String: Any]] {
            let list = codes.compactMap { $0["code"] as? String }
            values["dtc_count"] = String(list.count)
            values["dtc_list"] = list.joined(separator: "、")
        } else {
            values["dtc_count"] = "0"
            values["dtc_list"] = ""
        }

        // 定位
        if let loc = d["location"] as? [String: Any] {
            let la = Self.dbl(loc["lat"])
            let lo = Self.dbl(loc["lon"])
            if la != 0 || lo != 0 {
                lat = la
                lon = lo
                locStatus = "已定位"
                geocode()
            }
        } else if lat == 0 && lon == 0 {
            locStatus = "等待定位数据"
        }

        // 胎压
        if let tireDict = d["tires"] as? [String: Any] {
            let order = ["fl", "fr", "rl", "rr"]
            let names = ["左前", "右前", "左后", "右后"]
            var out: [TireInfo] = []
            for (i, key) in order.enumerated() {
                guard let t = tireDict[key] as? [String: Any] else { continue }
                let kpa = Self.dbl(t["kpa"])
                if kpa <= 0 { continue }
                out.append(TireInfo(
                    slot: i,
                    name: names[i],
                    kpa: kpa,
                    tempC: Self.dbl(t["temp"]),
                    battery: Self.dbl(t["battery"]),
                    alarm: (t["alarm"] as? String) ?? ""
                ))
            }
            if !out.isEmpty {
                tires = out
                tiresStale = false
                tiresCachedAt = Date()
                Self.saveTireCache(out)
            }
        }
        if tires.isEmpty {
            restoreTireCacheIfNeeded()
        }
    }

    static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    static func dbl(_ v: Any?) -> Double {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) ?? 0 }
        return 0
    }




    // MARK: 胎压本地缓存

    private static let tireCacheKey = "tireCache_v1"

    private static func saveTireCache(_ list: [TireInfo]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: tireCacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: tireCacheKey + "_at")
    }

    static func loadTireCache() -> (info: [TireInfo], at: Date)? {
        guard let data = UserDefaults.standard.data(forKey: tireCacheKey),
              let list = try? JSONDecoder().decode([TireInfo].self, from: data),
              !list.isEmpty else { return nil }
        let ts = UserDefaults.standard.double(forKey: tireCacheKey + "_at")
        let at = ts > 0 ? Date(timeIntervalSince1970: ts) : Date()
        return (list, at)
    }

    /// 启动时先把缓存显示出来，等新数据到了再覆盖
    func restoreTireCacheIfNeeded() {
        if tires.isEmpty, let cached = Self.loadTireCache() {
            tires = cached.info
            tiresCachedAt = cached.at
            tiresStale = true
        }
    }



    // MARK: 连接测试

    func testConnection() async {
        guard configured else { message = "请先填写服务地址和令牌"; return }
        guard let url = URL(string: base + "/api/health") else { message = "地址格式不对"; return }
        do {
            let (data, http) = try await Net.get(url, token: token)
            if http.statusCode == 200,
               let d = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let v = (d["version"] as? String) ?? "?"
                message = "连接正常 · 服务 v" + v
                connected = true
                reachable = true
            } else {
                message = "服务返回 " + String(http.statusCode)
                connected = false
            }
        } catch {
            message = "连不上：" + error.localizedDescription
            connected = false
        }
    }



    // MARK: 行程列表

    func loadTrips() async {
        guard configured else { tripsError = "未配置"; return }
        tripsLoading = true
        tripsError = ""
        defer { tripsLoading = false }

        guard let url = URL(string: base + "/api/trips?limit=200") else {
            tripsError = "地址格式不对"
            return
        }
        do {
            let (data, http) = try await Net.get(url, token: token)
            guard http.statusCode == 200 else {
                tripsError = "服务返回 " + String(http.statusCode)
                return
            }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = root["trips"] as? [[String: Any]] else {
                tripsError = "数据格式不对"
                return
            }
            let cal = Calendar.current
            let hhmm = DateFormatter(); hhmm.dateFormat = "HH:mm"
            let mdhm = DateFormatter(); mdhm.dateFormat = "MM-dd HH:mm"

            var out: [Trip] = []
            for r in rows {
                let st = Self.dbl(r["start_ts"])
                let et = Self.dbl(r["end_ts"])
                guard st > 0 else { continue }
                let sDate = Date(timeIntervalSince1970: st / 1000.0)
                let eDate = Date(timeIntervalSince1970: max(et, st) / 1000.0)
                let startText = cal.isDateInToday(sDate) ? hhmm.string(from: sDate) : mdhm.string(from: sDate)
                let sameDay = cal.isDate(sDate, inSameDayAs: eDate)
                let endText = (cal.isDateInToday(eDate) && sameDay) ? hhmm.string(from: eDate) : mdhm.string(from: eDate)
                out.append(Trip(
                    id: String(Int(Self.dbl(r["id"]))),
                    start: startText,
                    end: endText,
                    startTs: st,
                    endTs: et,
                    durationMin: Int(Self.dbl(r["duration_s"]) / 60.0),
                    distanceKm: Self.dbl(r["distance_km"]),
                    maxSpeed: Self.dbl(r["max_speed"]),
                    avgSpeed: Self.dbl(r["avg_speed"]),
                    maxCoolant: Self.dbl(r["max_coolant"]),
                    minVoltage: Self.dbl(r["min_voltage"]),
                    file: (r["csv_name"] as? String) ?? ""
                ))
            }
            trips = out.sorted { $0.startTs > $1.startTs }
            if trips.isEmpty { tripsError = "暂无行程" }
        } catch {
            if error is CancellationError { return }
            tripsError = "加载失败：" + error.localizedDescription
        }
    }

    /// 行程曲线：从服务端拉降采样序列
    private func tripSeries(_ trip: Trip) async -> [[String: Any]] {
        guard configured, let url = URL(string: base + "/api/trips/" + trip.id) else { return [] }
        do {
            let (data, http) = try await Net.get(url, token: token)
            guard http.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let series = root["series"] as? [[String: Any]] else { return [] }
            return series
        } catch {
            return []
        }
    }



    /// 行程曲线：从车况服务拉降采样序列
    func tripSpeeds(_ trip: Trip) async -> [Double] {
        let series = await tripSeries(trip)
        return series.compactMap { $0["speed"] as? NSNumber }.map { $0.doubleValue }
    }



    private func parseSpeedCsv(_ text: String) -> [Double] {
        var out: [Double] = []
        for line in text.components(separatedBy: "\n") {
            let parts = line.split(separator: ",")
            guard parts.count >= 4, Double(parts[1]) != nil else { continue }
            if let v = Double(parts[3]) { out.append(v) }
        }
        return out
    }

    /// 某段行程内某项数据的采样值
    func tripSamples(_ trip: Trip, key: String) async -> [Double] {
        let series = await tripSeries(trip)
        return series.compactMap { ($0[key] as? NSNumber)?.doubleValue }
    }



    // MARK: 定位


    private func geocode() {
        if geocoderBusy { return }
        if let t = lastGeocode, Date().timeIntervalSince(t) < 120 { return }
        geocoderBusy = true
        lastGeocode = Date()
        let loc = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
            Task { @MainActor in
                if let p = placemarks?.first {
                    let parts = [p.administrativeArea, p.locality, p.subLocality, p.name]
                        .compactMap { $0 }
                    if !parts.isEmpty { self.locAddress = parts.joined(separator: " ") }
                }
                self.geocoderBusy = false
            }
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
