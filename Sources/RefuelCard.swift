import SwiftUI

// MARK: - 数据模型（对应服务端 /api/refuel/list）

struct RefuelItem: Codable, Identifiable {
    var id: Int = 0
    var ts: Double = 0
    var odo: Double = 0
    var liters: Double = 0
    var price: Double? = nil
    var amount: Double? = nil
    var lPer100km: Double? = nil
    var trips: Int = 0
    var tripsKm: Double = 0
    var source: String = "auto"
    var date: String = ""
    var tripList: [RefuelTrip] = []

    enum CodingKeys: String, CodingKey {
        case id, ts, odo, liters, price, amount, trips, source, date
        case lPer100km = "l_per_100km"
        case tripsKm = "trips_km"
        case tripList = "trip_list"
    }
}

struct RefuelTrip: Codable, Identifiable {
    var id: Int = 0
    var start: String = ""
    var end: String = ""
    var distanceKm: Double = 0

    enum CodingKeys: String, CodingKey {
        case id, start, end
        case distanceKm = "distance_km"
    }
}

// MARK: - 车况页卡片

struct RefuelCard: View {
    let items: [RefuelItem]
    var onTap: () -> Void = {}

    private var last: RefuelItem? { items.first }

    private var litersText: String {
        guard let l = last else { return "--" }
        return String(format: "%.1f", l.liters)
    }

    private var kplText: String {
        guard let k = last?.lPer100km else { return "--" }
        return String(format: "%.1f", k)
    }

    private var dateText: String {
        guard let d = last?.date, !d.isEmpty else { return "还没有记录" }
        return String(d.suffix(11))          // "11-09 23:49"
    }

    var body: some View {
        Button(action: onTap) {
            SoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "fuelpump.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.blue)
                        Text("加油记录")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.ink)
                        Spacer(minLength: 0)
                        if let l = last {
                            Text(l.source == "auto" ? "自动识别" : "手动")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.sub)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.sub.opacity(0.12)))
                        }
                    }

                    if items.isEmpty {
                        Text("还没有加油记录。车机上报油量上涨 ≥8L（停车状态）会自动记一条。")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 10) {
                            RefuelCell(big: litersText, unit: "L", caption: dateText)
                            RefuelCell(big: kplText, unit: "L/100km", caption: "上次油耗",
                                       tint: last?.lPer100km == nil ? Theme.sub : Theme.ink)
                        }
                    }
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.98, dim: 1.0))
    }
}

private struct RefuelCell: View {
    let big: String
    let unit: String
    let caption: String
    var tint: Color = Theme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(big)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.sub)
            }
            Text(caption)
                .font(.system(size: 11))
                .foregroundColor(Theme.sub)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.bgMid.opacity(0.55))
        )
    }
}

// MARK: - 二级页：加油记录列表

struct RefuelSheet: View {
    let items: [RefuelItem]
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<Int> = []

    private var monthKey: (RefuelItem) -> String {
        { String($0.date.prefix(7)) }     // "2026-11"
    }

    private var grouped: [(String, [RefuelItem])] {
        var order: [String] = []
        var map: [String: [RefuelItem]] = [:]
        for it in items {
            let k = monthKey(it)
            if map[k] == nil { order.append(k); map[k] = [] }
            map[k]?.append(it)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private var monthStat: (count: Int, liters: Double, amount: Double, avg: Double?) {
        let nowKey = String(ISO8601DateFormatter().string(from: Date()).prefix(7))
        let rows = items.filter { monthKey($0) == nowKey }
        let liters = rows.reduce(0) { $0 + $1.liters }
        let amount = rows.reduce(0) { $0 + ($1.amount ?? 0) }
        let kons = rows.compactMap { $0.lPer100km }
        let avg = kons.isEmpty ? nil : kons.reduce(0, +) / Double(kons.count)
        return (rows.count, liters, amount, avg)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("加油记录")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.ink)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.sub)
                            .padding(8)
                            .background(Circle().fill(Theme.card))
                    }
                }

                let ms = monthStat
                Text("本月 \(ms.count) 次 · \(String(format: "%.1f", ms.liters)) L · \(String(format: "%.0f", ms.amount)) 元"
                     + (ms.avg.map { String(format: " · 均 %.1f L/100km", $0) } ?? ""))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.sub)

                if items.isEmpty {
                    Text("还没有记录")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.sub)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }

                ForEach(grouped, id: \.0) { month, rows in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(monthTitle(month))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.sub)

                        ForEach(rows) { r in
                            RefuelRow(item: r,
                                      open: expanded.contains(r.id),
                                      toggle: {
                                          if expanded.contains(r.id) { expanded.remove(r.id) }
                                          else { expanded.insert(r.id) }
                                      })
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .background(AppBackground())
    }

    private func monthTitle(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2 else { return key }
        return "\(parts[0]) 年 \(Int(parts[1]) ?? 0) 月"
    }
}

private struct RefuelRow: View {
    let item: RefuelItem
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.date.suffix(11))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.ink)
                        Text(String(format: "%.0f km", item.odo))
                            .font(.system(size: 11))
                            .foregroundColor(Theme.sub)
                        Spacer(minLength: 0)
                        if item.trips > 0 {
                            Image(systemName: open ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.sub)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", item.liters))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.ink)
                        Text("L")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.sub)

                        Spacer(minLength: 6)

                        if let amt = item.amount {
                            Text(String(format: "%.0f 元", amt))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.ink)
                        }
                        if let k = item.lPer100km {
                            Text(String(format: "· %.1f L/100km", k))
                                .font(.system(size: 12))
                                .foregroundColor(Theme.sub)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if open && item.trips > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.tripList) { t in
                        HStack(spacing: 6) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Theme.blue.opacity(0.8))
                            Text("\(t.start) – \(t.end)")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.sub)
                            Spacer(minLength: 0)
                            Text(String(format: "%.1f km", t.distanceKm))
                                .font(.system(size: 11))
                                .foregroundColor(Theme.sub)
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.leading, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card.opacity(0.92))
        )
    }
}
