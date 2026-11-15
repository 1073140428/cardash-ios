import SwiftUI

// MARK: - 弧形仪表

struct ArcGauge: View {
    let value: Double?
    let maxValue: Double
    let title: String
    let unit: String
    var primary: Bool = false

    private var fraction: Double {
        guard let v = value else { return 0 }
        return min(max(v, 0), maxValue) / max(maxValue, 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let side = min(w, h)
            let thick: CGFloat = primary ? 14 : 12
            let radius = side / 2 - thick / 2 - 2
            let span = 240.0          // 弧度范围（度）
            let startDeg = 150.0

            ZStack {
                // 刻度：主刻度每 1/8，副刻度每 1/40
                ForEach(0..<41, id: \.self) { i in
                    let frac = Double(i) / 40.0
                    let major = i % 5 == 0
                    Rectangle()
                        .fill(Theme.sub.opacity(major ? 0.45 : 0.20))
                        .frame(width: major ? 1.8 : 1.2, height: major ? 7 : 4)
                        .offset(y: -(radius - thick / 2 - (major ? 9 : 7)))
                        .rotationEffect(.degrees(startDeg + span * frac))
                }

                // 三个数字（0 / 一半 / 满量程）
                ForEach(0..<3, id: \.self) { k in
                    let frac = Double(k) / 2.0
                    let angle = (startDeg + span * frac - 90) * .pi / 180
                    let r = radius - 22
                    Text(scaleLabel(frac))
                        .font(.system(size: primary ? 11 : 9, weight: .medium))
                        .foregroundColor(Theme.sub.opacity(0.85))
                        .position(x: w / 2 + CGFloat(cos(angle)) * r,
                                  y: h / 2 + CGFloat(sin(angle)) * r)
                }

                // 底弧
                Circle()
                    .trim(from: 0, to: span / 360.0)
                    .stroke(Theme.line, style: StrokeStyle(lineWidth: thick, lineCap: .round))
                    .rotationEffect(.degrees(startDeg))
                    .padding(side / 2 - radius - thick / 2 + 2)

                // 数值弧
                Circle()
                    .trim(from: 0, to: span / 360.0 * fraction)
                    .stroke(
                        LinearGradient(colors: [Theme.blueSoft, Theme.blue],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: thick, lineCap: .round))
                    .rotationEffect(.degrees(startDeg))
                    .padding(side / 2 - radius - thick / 2 + 2)

                VStack(spacing: 0) {
                    Text(title)
                        .font(.system(size: primary ? 14 : 11, weight: .medium))
                        .foregroundColor(Theme.sub)
                    Text(value == nil ? "--" : String(format: "%.0f", value!))
                        .font(.system(size: primary ? 46 : 30, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.ink)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                    Text(unit)
                        .font(.system(size: primary ? 12 : 9))
                        .foregroundColor(Theme.sub)
                }
            }
            .frame(width: w, height: h)
        }
    }

    private func scaleLabel(_ frac: Double) -> String {
        let v = maxValue * frac
        if maxValue >= 1000 { return String(format: "%.0f", v / 1000) }   // 转速用千转
        return String(format: "%.0f", v)
    }
}

/// 没数据 → "--"，真实 0 → "0.0"
func fmtOrDash(_ v: Double?, _ f: String) -> String {
    guard let v = v else { return "--" }
    return String(format: f, v)
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
            VStack(spacing: 9) {
                // 顶部：车模缩小放左上，右侧标题 + 在线状态 + 自动刷新胶囊
                HStack(alignment: .top, spacing: 10) {
                    Image("car")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 58)

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 7) {
                        HStack(spacing: 5) {
                            Text("实时仪表")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(Theme.ink)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.sub.opacity(0.7))
                            Text(store.connected ? "在线" : "离线")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(store.connected ? Theme.good : Theme.sub)
                        }
                        Text(store.connected ? "自动刷新中" : "已断开")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.blueDeep)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.blue.opacity(0.10)))
                    }
                }
                .padding(.top, 2)

                HStack(spacing: 10) {
                    ArcGauge(value: store.speedOpt, maxValue: 220,
                             title: "车速", unit: "km/h")
                        .frame(height: 142)

                    ArcGauge(value: store.rpmOpt, maxValue: 8000,
                             title: "转速", unit: "rpm")
                        .frame(height: 142)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ValueCard(title: "节气门",
                              value: fmtOrDash(store.throttleOpt, "%.1f"),
                              unit: "%", symbol: "wind")
                    ValueCard(title: "进气压力",
                              value: fmtOrDash(store.mapOpt, "%.0f"),
                              unit: "kPa", symbol: "arrow.down.circle", tint: Theme.good)
                    ValueCard(title: "发动机负荷",
                              value: fmtOrDash(store.loadOpt, "%.1f"),
                              unit: "%", symbol: "chart.bar.fill")
                    ValueCard(title: "点火提前角",
                              value: fmtOrDash(store.timingOpt, "%.1f"),
                              unit: "°", symbol: "bolt.fill")
                }

                WeekKmCard(days: store.weekKm, total: store.weekTotal, avg: store.weekAvg)

            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }
}
