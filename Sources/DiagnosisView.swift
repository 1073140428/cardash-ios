import SwiftUI

struct StatusCard: View {
    let symbol: String
    let title: String
    let status: String
    let value: String
    var ok: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.blue.opacity(0.10))
                        .frame(width: 32, height: 32)
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.blue)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(status)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ok ? Theme.good : Theme.warn)
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.card.opacity(0.92))
        )
        .shadow(color: Theme.blueDeep.opacity(0.06), radius: 10, x: 0, y: 6)
    }
}

struct TireCell: View {
    let t: TireInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(t.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.sub)
                Spacer(minLength: 0)
                Text(t.ok ? "正常" : t.alarm)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(t.ok ? Theme.good : Theme.warn)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.2f", t.bar))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(t.ok ? Theme.ink : Theme.warn)
                Text("bar")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.sub)
            }
            Text(String(format: "%.0f°C · ", t.tempC) + battText(t.battery))
                .font(.system(size: 11))
                .foregroundColor(Theme.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.bgMid.opacity(0.55))
        )
    }
}

private func shortTime(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: d)
}

struct DiagnosisView: View {
    @EnvironmentObject var store: CarStore
    @State private var result: String? = nil
    @State private var showDtc = false

    private var voltOk: Bool { store.volt == 0 || store.volt >= 11.8 }
    private var waterOk: Bool { store.coolant == 0 || store.coolant <= 100 }
    private var fuelOk: Bool { store.fuel == 0 || store.fuel >= 8 }
    private var dtcCount: Int { Int(store.values["dtc_count"] ?? "0") ?? 0 }
    private var dtcList: String {
        let v = store.values["dtc_list"] ?? ""
        return v.isEmpty ? "已读" : v
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                PageHeader(
                    title: "车况诊断",
                    subtitle: store.updatedText,
                    badge: store.connected ? "已连接" : "未连接",
                    badgeOn: store.connected
                )

                CarHero(height: 115)

                if !store.tires.isEmpty {
                    SoftCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "car.side.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.blue)
                                Text("胎压监测")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Theme.ink)
                                Spacer()
                                if store.tiresStale, let at = store.tiresCachedAt {
                                    Text("上次 " + shortTime(at))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Theme.sub)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Theme.sub.opacity(0.12)))
                                } else {
                                    Text("\(store.tires.count) 轮")
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.sub)
                                }
                            }
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ], spacing: 10) {
                                ForEach(store.tires) { t in
                                    TireCell(t: t)
                                }
                            }
                        }
                    }
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    StatusCard(symbol: "battery.100", title: "电池系统",
                               status: voltOk ? "正常" : "偏低",
                               value: unitOrDash(store.voltOpt, "%.1f", " V"), ok: voltOk)

                    StatusCard(symbol: "thermometer", title: "冷却系统",
                               status: waterOk ? "正常" : "偏高",
                               value: unitOrDash(store.coolantOpt, "%.0f", " °C"), ok: waterOk)

                    StatusCard(symbol: "drop.fill", title: "燃油系统",
                               status: fuelOk ? "正常" : "偏低",
                               value: unitOrDash(store.fuelOpt, "%.1f", " L"), ok: fuelOk)

                    StatusCard(symbol: "gauge", title: "发动机系统",
                               status: store.rpm > 0 ? "运转中" : "未启动",
                               value: unitOrDash(store.rpmOpt, "%.0f", " rpm"), ok: true)

                    StatusCard(symbol: "wind", title: "节气门",
                               status: store.throttle > 0 ? "工作" : "怠速",
                               value: unitOrDash(store.throttleOpt, "%.1f", " %"), ok: true)

                    Button {
                        if dtcCount > 0 { showDtc = true }
                    } label: {
                        StatusCard(symbol: "checkmark.shield.fill", title: "故障码",
                                   status: dtcCount == 0 ? "无" : "\(dtcCount) 个",
                                   value: dtcCount == 0 ? (store.connected ? "已读" : "--") : dtcList,
                                   ok: dtcCount == 0)
                    }
                    .buttonStyle(PressableStyle(scale: 0.96, dim: 0.85))
                }

                if let r = result {
                    Text(r)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.blue.opacity(0.08))
                        )
                }

                PrimaryButton(title: "开始诊断") {
                    result = runCheck()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .sheet(isPresented: $showDtc) {
            DtcSheet(items: store.dtcItems, at: store.dtcAt)
        }
    }

    private func runCheck() -> String {
        if !store.connected { return "未连接到车况服务，无法诊断。" }
        var issues: [String] = []
        if !voltOk { issues.append("电瓶电压偏低（\(String(format: "%.1f", store.volt)) V）") }
        if !waterOk { issues.append("水温偏高（\(String(format: "%.0f", store.coolant)) °C）") }
        if !fuelOk { issues.append("油量偏低（\(String(format: "%.1f", store.fuel)) L）") }
        if issues.isEmpty { return "诊断完成：电压、水温、油量均在正常范围，未发现异常。" }
        return "诊断完成，发现 " + String(issues.count) + " 项提示：" + issues.joined(separator: "；")
    }
}


// MARK: - 故障码详情

struct DtcSheet: View {
    let items: [DtcItem]
    let at: Date?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(items) { d in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(d.code)
                                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                                    .foregroundColor(.red)
                                if !d.title.isEmpty {
                                    Text(d.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Theme.ink)
                                }
                                Spacer()
                            }
                            if !d.desc.isEmpty {
                                Text(d.desc)
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.ink)
                            }
                            if !d.causes.isEmpty {
                                row("可能原因", d.causes)
                            }
                            if !d.checks.isEmpty {
                                row("检查项", d.checks)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.bgMid)
                        )
                    }

                    if let t = at {
                        Text("读取时间 " + t.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundColor(Theme.sub)
                            .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .background(Theme.bgMid.ignoresSafeArea())
            .navigationTitle("故障码详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.sub)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 没数据 → "--"，有数据 → 数值 + 单位
func unitOrDash(_ v: Double?, _ f: String, _ unit: String) -> String {
    guard let v = v else { return "--" }
    return String(format: f, v) + unit
}

/// 胎压传感器电池：设备多按 0.1V 上报（26 → 2.6V），兼容 mV 与直接伏特
func battText(_ v: Double) -> String {
    if v <= 0 { return "--" }
    if v >= 20 && v <= 45 { return String(format: "%.1fV", v / 10) }
    if v > 100 { return String(format: "%.2fV", v / 1000) }
    return String(format: "%.2fV", v)
}
