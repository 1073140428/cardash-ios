import SwiftUI

// MARK: - 车速折线

struct SpeedChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let mx = max(values.max() ?? 1, 1)

            let pts: [CGPoint] = values.enumerated().map { i, v in
                let x = values.count > 1 ? w * CGFloat(i) / CGFloat(values.count - 1) : 0
                let ratio = CGFloat(min(max(v, 0), mx) / mx)
                return CGPoint(x: x, y: h - h * ratio)
            }

            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: h))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Theme.blue.opacity(0.22), Theme.blue.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(Theme.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                } else {
                    Text("暂无历史数据")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.sub)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: 150)
    }
}

// MARK: - 行程页

struct TripView: View {
    @EnvironmentObject var store: CarStore
    @State private var appeared = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                PageHeader(
                    title: "行程统计",
                    subtitle: "最近 6 小时",
                    badge: store.connected ? "已连接" : "未连接",
                    badgeOn: store.connected
                )

                SoftCard(padding: 10) {
                    CarHero(height: 150)
                }

                HStack(spacing: 10) {
                    ValueCard(title: "平均车速",
                              value: store.tripAvgSpeed.map { String(format: "%.0f", $0) } ?? "--",
                              unit: "km/h", symbol: "speedometer")
                    ValueCard(title: "行驶里程",
                              value: store.tripDistance.map { String(format: "%.1f", $0) } ?? "--",
                              unit: "km", symbol: "road.lanes")
                }

                HStack(spacing: 10) {
                    ValueCard(title: "最高车速",
                              value: store.tripMaxSpeed.map { String(format: "%.0f", $0) } ?? "--",
                              unit: "km/h", symbol: "arrow.up.right")
                    ValueCard(title: "当前油量",
                              value: String(format: "%.1f", store.fuel),
                              unit: "L", symbol: "drop.fill")
                }

                SoftCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("车速趋势")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.ink)
                            Spacer()
                            if store.historyLoading {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Button(action: {
                                    Task { await store.loadHistory(force: true) }
                                }) {
                                    Text("刷新")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Theme.blue)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        SpeedChart(values: store.speedHistory)

                        if !store.historyError.isEmpty {
                            Text(store.historyError)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.sub)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .onAppear {
            if !appeared {
                appeared = true
                Task { await store.loadHistory() }
            }
        }
    }
}
