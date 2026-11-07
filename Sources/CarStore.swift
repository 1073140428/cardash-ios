import SwiftUI
import CoreLocation

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
            message = "请到「设置」填写 HA 地址和令牌"
            connected = false
            return
        }

        var ok = 0
        reachable = false
        lastErr = ""
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
        if let ls = await fetchState("obd_loc") {
            locStatus = ls
        }
        await refreshLocation()
        await refreshTires()

        connected = reachable
        if ok == 0 {
            message = lastErr.isEmpty
                ? (connected ? "已连上 HA，但还没有车辆数据（车机未上报）" : "连不上服务器")
                : lastErr
        } else {
            message = ""
            lastUpdate = Date()
        }
    }

    private func refreshTires() async {
        let keys = ["tp_fl", "tp_fr", "tp_rl", "tp_rr"]
        let names = ["左前", "右前", "左后", "右后"]
        var out: [TireInfo] = []
        for i in 0..<keys.count {
            guard let obj = await fetchFull("sensor." + keys[i]) else { continue }
            let a = (obj["attributes"] as? [String: Any]) ?? [:]
            let kpa = Double(obj["state"] as? String ?? "") ?? 0
            if kpa <= 0 { continue }
            out.append(TireInfo(
                slot: i,
                name: names[i],
                kpa: kpa,
                tempC: (a["temp_c"] as? NSNumber)?.doubleValue ?? 0,
                battery: (a["battery"] as? NSNumber)?.doubleValue ?? 0,
                alarm: (a["alarm"] as? String) ?? ""
            ))
        }
        if out.isEmpty {
            // HA 重启后 sensor.tp_* 虚拟实体会消失，这里回落到上次缓存，避免卡片闪没
            if let cached = Self.loadTireCache() {
                tires = cached.info
                tiresCachedAt = cached.at
                tiresStale = true
            } else {
                tires = []
                tiresStale = false
            }
        } else {
            tires = out
            tiresStale = false
            tiresCachedAt = Date()
            Self.saveTireCache(out)
        }
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

    private func fetchFull(_ entity: String) async -> [String: Any]? {
        guard let url = URL(string: base + "/api/states/" + entity) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private func fetchState(_ key: String) async -> String? {
        guard let url = URL(string: base + "/api/states/sensor." + key) else {
            lastErr = "地址格式不对：" + base
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return nil }
            if http.statusCode == 401 || http.statusCode == 403 {
                lastErr = "令牌无效或被拒绝（HTTP \(http.statusCode)）"
                return nil
            }
            reachable = true
            if http.statusCode == 404 {
                return nil
            }
            if http.statusCode != 200 {
                lastErr = "HTTP \(http.statusCode)"
                return nil
            }
            return try JSONDecoder().decode(HAStateResp.self, from: data).state
        } catch {
            lastErr = "连不上：\(error.localizedDescription)"
            return nil
        }
    }

    // MARK: 连接测试

    func testConnection() async {
        guard configured else {
            message = "地址或令牌为空"
            return
        }
        guard let url = URL(string: base + "/api/") else {
            message = "地址格式不对：" + base
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = (String(data: data, encoding: .utf8) ?? "").prefix(50)
            message = "HTTP \(code) · \(body)"
        } catch {
            message = "失败：\(error.localizedDescription)"
        }
    }

    // MARK: 行程列表

    func loadTrips() async {
        guard configured else { tripsError = "未配置"; return }
        tripsLoading = true
        tripsError = ""
        defer { tripsLoading = false }

        let df = ISO8601DateFormatter()
        var allRows: [[String: Any]] = []
        var cancelled = false
        let now = Date()

        // HA 的历史接口跨度超过约 1 天会返回空数组，所以按天分段查
        for day in 0..<7 {
            let end = now.addingTimeInterval(-Double(day) * 86400)
            let start = end.addingTimeInterval(-86400)
            let path = base + "/api/history/period/" + df.string(from: start)
                + "?filter_entity_id=sensor.obd_trip&end_time=" + df.string(from: end)
            guard let url = URL(string: path) else { continue }

            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
                if let root = try JSONSerialization.jsonObject(with: data) as? [[[String: Any]]],
                   let rows = root.first {
                    allRows.append(contentsOf: rows)
                }
            } catch {
                if error is CancellationError { cancelled = true }
                continue
            }
        }

        if allRows.isEmpty && cancelled {
            // 被取消（如下拉刷新手势结束）时不要清空已有列表
            return
        }

        if allRows.isEmpty {
            trips = []
            tripsError = "暂无行程"
            return
        }

        var out: [Trip] = []
        var seen = Set<String>()
        for r in allRows {
            guard let a = r["attributes"] as? [String: Any] else { continue }
            let st = dbl(a["start_ts"])
            if st <= 0 { continue }
            let key = String(format: "%.0f", st)
            if seen.contains(key) { continue }
            seen.insert(key)

            // 时间显示不依赖车机写的字符串：今天只显示 HH:mm，非今天带 MM-dd
            let et = dbl(a["end_ts"])
            let sDate = Date(timeIntervalSince1970: st / 1000.0)
            let eDate = Date(timeIntervalSince1970: max(et, st) / 1000.0)
            let hhmm = DateFormatter()
            hhmm.dateFormat = "HH:mm"
            let mdhm = DateFormatter()
            mdhm.dateFormat = "MM-dd HH:mm"
            let cal = Calendar.current
            let startText = cal.isDateInToday(sDate) ? hhmm.string(from: sDate) : mdhm.string(from: sDate)
            let sameDay = cal.isDate(sDate, inSameDayAs: eDate)
            let endText = (cal.isDateInToday(eDate) && sameDay) ? hhmm.string(from: eDate) : mdhm.string(from: eDate)

            out.append(Trip(
                id: key,
                start: startText,
                end: endText,
                startTs: st,
                endTs: dbl(a["end_ts"]),
                durationMin: Int(dbl(a["duration_min"])),
                distanceKm: dbl(a["distance_km"]),
                maxSpeed: dbl(a["max_speed"]),
                avgSpeed: dbl(a["avg_speed"]),
                maxCoolant: dbl(a["max_coolant"]),
                minVoltage: dbl(a["min_voltage"]),
                file: (a["file"] as? String) ?? ""
            ))
        }

        trips = out.sorted { $0.startTs > $1.startTs }
        if trips.isEmpty { tripsError = "暂无行程" }
    }

    /// 行程曲线：优先下载车机上传到 HA 的 csv，失败再退回 HA 历史采样
    func tripSpeeds(_ trip: Trip) async -> [Double] {
        if !trip.file.isEmpty {
            let enc = trip.file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trip.file
            if let url = URL(string: base + "/local/trips/" + enc) {
                var req = URLRequest(url: url)
                req.timeoutInterval = 20
                do {
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    if (resp as? HTTPURLResponse)?.statusCode == 200,
                       let text = String(data: data, encoding: .utf8) {
                        let vals = parseSpeedCsv(text)
                        if !vals.isEmpty { return vals }
                    }
                } catch {
                }
            }
        }
        return await tripSamples(trip, key: "obd_speed")
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

    // MARK: 定位

    private func refreshLocation() async {
        guard let url = URL(string: base + "/api/states/device_tracker.obd_car") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let attrs = obj["attributes"] as? [String: Any] else { return }
            let la = dbl(attrs["latitude"])
            let lo = dbl(attrs["longitude"])
            if la != 0 && lo != 0 {
                let moved = abs(la - lat) > 0.0003 || abs(lo - lon) > 0.0003
                lat = la
                lon = lo
                if moved || locAddress.isEmpty { geocode() }
            }
        } catch {
            // 静默失败，位置保持上一次
        }
    }

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
