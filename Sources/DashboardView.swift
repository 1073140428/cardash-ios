import SwiftUI

// MARK: - 弧形仪表

struct ArcGauge: View {
    let value: Double
    let maxValue: Double
    let title: String
    let unit: String
    var primary: Bool = false

    private var fraction: Double {
        min(max(value, 0), maxValue) / max(maxValue, 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.667)
                .stroke(Theme.line,
                        style: StrokeStyle(lineWidth: primary ? 16 : 12, lineCap: .round))
                .rotationEffect(.degrees(150))
                .padding(primary ? 18 : 13)

            Circle()
                .trim(from: 0, to: 0.667 * fraction)
                .stroke(
                    LinearGradient(colors: [Theme.blueSoft, Theme.blue],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: primary ? 16 : 12, lineCap: .round)
                )
                .rotationEffect(.degrees(150))
                .padding(primary ? 18 : 13)

            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: primary ? 15 : 12, weight: .medium))
                    .foregroundColor(Theme.sub)
                Text(String(format: "%.0f", value))
                    .font(.system(size: primary ? 68 : 34, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.ink)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: primary ? 15 : 10))
                    .foregroundColor(Theme.sub)
            }
        }
    }
}

// MARK: - 小数值卡

struct MiniStat: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(Theme.blue.opacity(0.10)).frame(width: 32, height: 32)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.blue)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11)).foregroundColor(Theme.sub)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit).font(.system(size: 10)).foregroundColor(Theme.sub)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Theme.card.opacity(0.92))
        )
        .shadow(color: Theme.blueDeep.opacity(0.06), radius: 8, x: 0, y: 5)
    }
}

// MARK: - 仪表页
// 布局：车模在上 → 左车速表 / 右转速表 → 两排四张卡

struct DashboardView: View {
    @EnvironmentObject var store: CarStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                PageHeader(
                    title: "实时仪表",
                    subtitle: "\(store.obdState) · \(store.updatedText)",
                    badge: store.connected ? "已连接" : "未连接",
                    badgeOn: store.connected
                )

                CarHero(height: 118)

                HStack(spacing: 10) {
                    ArcGauge(value: store.speed, maxValue: 220,
                             title: "车速", unit: "km/h")
                        .frame(height: 150)

                    ArcGauge(value: store.rpm, maxValue: 8000,
                             title: "转速", unit: "rpm")
                        .frame(height: 150)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ValueCard(title: "节气门",
                              value: String(format: "%.1f", store.throttle),
                              unit: "%", symbol: "wind")
                    ValueCard(title: "进气压力",
                              value: String(format: "%.0f", store.map),
                              unit: "kPa", symbol: "arrow.down.circle", tint: Theme.good)
                    ValueCard(title: "发动机负荷",
                              value: String(format: "%.1f", store.load),
                              unit: "%", symbol: "chart.bar.fill")
                    ValueCard(title: "点火提前角",
                              value: String(format: "%.1f", store.timing),
                              unit: "°", symbol: "bolt.fill")
                }

                PrimaryButton(title: "刷新数据") {
                    Task { await store.refresh() }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }
}
