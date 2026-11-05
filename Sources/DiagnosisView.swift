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
                    .foregroundColor(ok ? Theme.good : Color(hex: "F08A24"))
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
                .fill(Color.white.opacity(0.92))
        )
        .shadow(color: Theme.blueDeep.opacity(0.06), radius: 10, x: 0, y: 6)
    }
}

struct DiagnosisView: View {
    @EnvironmentObject var store: CarStore
    @State private var result: String? = nil

    private var voltOk: Bool { store.volt == 0 || store.volt >= 11.8 }
    private var waterOk: Bool { store.coolant == 0 || store.coolant <= 100 }
    private var fuelOk: Bool { store.fuel == 0 || store.fuel >= 8 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                PageHeader(
                    title: "车况诊断",
                    subtitle: "基于最近一次上传的数据",
                    badge: store.connected ? "已连接" : "未连接",
                    badgeOn: store.connected
                )

                CarHero(height: 115)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    StatusCard(symbol: "battery.100", title: "电池系统",
                               status: voltOk ? "正常" : "偏低",
                               value: String(format: "%.1f V", store.volt), ok: voltOk)

                    StatusCard(symbol: "thermometer", title: "冷却系统",
                               status: waterOk ? "正常" : "偏高",
                               value: String(format: "%.0f °C", store.coolant), ok: waterOk)

                    StatusCard(symbol: "drop.fill", title: "燃油系统",
                               status: fuelOk ? "正常" : "偏低",
                               value: String(format: "%.1f L", store.fuel), ok: fuelOk)

                    StatusCard(symbol: "gauge", title: "发动机系统",
                               status: store.rpm > 0 ? "运转中" : "未启动",
                               value: String(format: "%.0f rpm", store.rpm), ok: true)

                    StatusCard(symbol: "wind", title: "节气门",
                               status: store.throttle > 0 ? "工作" : "怠速",
                               value: String(format: "%.1f %%", store.throttle), ok: true)

                    StatusCard(symbol: "checkmark.shield.fill", title: "故障码",
                               status: "无",
                               value: store.connected ? "已读" : "--", ok: true)
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
    }

    private func runCheck() -> String {
        if !store.connected { return "未连接到 Home Assistant，无法诊断。" }
        var issues: [String] = []
        if !voltOk { issues.append("电瓶电压偏低（\(String(format: "%.1f", store.volt)) V）") }
        if !waterOk { issues.append("水温偏高（\(String(format: "%.0f", store.coolant)) °C）") }
        if !fuelOk { issues.append("油量偏低（\(String(format: "%.1f", store.fuel)) L）") }
        if issues.isEmpty { return "诊断完成：电压、水温、油量均在正常范围，未发现异常。" }
        return "诊断完成，发现 " + String(issues.count) + " 项提示：" + issues.joined(separator: "；")
    }
}
