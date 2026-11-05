import SwiftUI

// MARK: - 速度表盘

struct SpeedGauge: View {
    let speed: Double
    let maxSpeed: Double = 180

    private var fraction: Double {
        min(max(speed, 0), maxSpeed) / maxSpeed
    }

    var body: some View {
        ZStack {
            // 底弧
            Circle()
                .trim(from: 0, to: 0.667)
                .stroke(Color(hex: "D9E6FA"), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(150))
                .padding(18)

            // 进度弧
            Circle()
                .trim(from: 0, to: 0.667 * fraction)
                .stroke(
                    LinearGradient(colors: [Theme.blueSoft, Theme.blue],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(150))
                .padding(18)

            VStack(spacing: 0) {
                Text("车速")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.sub)
                Text(String(format: "%.0f", speed))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("km/h")
                    .font(.system(size: 15))
                    .foregroundColor(Theme.sub)
            }
        }
    }
}

// MARK: - 小型数值卡

struct MiniStat: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.blue.opacity(0.10)).frame(width: 36, height: 36)
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.blue)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12)).foregroundColor(Theme.sub)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit).font(.system(size: 11)).foregroundColor(Theme.sub)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .shadow(color: Theme.blueDeep.opacity(0.06), radius: 8, x: 0, y: 5)
    }
}

// MARK: - 仪表页

struct DashboardView: View {
    @EnvironmentObject var store: CarStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                PageHeader(
                    title: "实时仪表",
                    subtitle: store.driving ? "行驶中 · \(store.updatedText)" : "已熄火 · \(store.updatedText)",
                    badge: store.connected ? "已连接" : "未连接",
                    badgeOn: store.connected
                )

                SpeedGauge(speed: store.speed)
                    .frame(height: 250)
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    MiniStat(title: "转速", value: String(format: "%.0f", store.rpm), unit: "rpm", symbol: "gauge")
                    MiniStat(title: "总里程", value: String(format: "%.0f", store.odo), unit: "km", symbol: "map")
                }

                CarHero(height: 160)

                HStack(spacing: 10) {
                    ValueCard(title: "油量", value: String(format: "%.1f", store.fuel),
                              unit: "L", symbol: "drop.fill")
                    ValueCard(title: "水温", value: String(format: "%.0f", store.water),
                              unit: "°C", symbol: "thermometer", tint: Color(hex: "FF7A59"))
                    ValueCard(title: "电压", value: String(format: "%.1f", store.volt),
                              unit: "V", symbol: "bolt.fill", tint: Theme.good)
                }

                PrimaryButton(title: "刷新数据") {
                    Task { await store.refresh() }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }
}
