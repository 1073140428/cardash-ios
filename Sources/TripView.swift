import SwiftUI

// MARK: - 折线

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
                    .fill(LinearGradient(colors: [Theme.blue.opacity(0.22), Theme.blue.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))

                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(Theme.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                } else {
                    Text("暂无采样数据")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.sub)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: 140)
    }
}

// MARK: - 行

struct TripRow: View {
    let trip: Trip

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.blue.opacity(0.10))
                    .frame(width: 44, height: 44)
                Image(systemName: "car.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("\(trip.start) → \(trip.end)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                Text("\(trip.durationMin) 分钟 · 最高 \(Int(trip.maxSpeed)) km/h")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.sub)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f", trip.distanceKm))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.ink)
                Text("km").font(.system(size: 10)).foregroundColor(Theme.sub)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card.opacity(0.92))
        )
        .shadow(color: Theme.blueDeep.opacity(0.06), radius: 8, x: 0, y: 5)
    }
}

// MARK: - 行程页

struct TripView: View {
    @EnvironmentObject var store: CarStore
    @State private var selected: Trip? = nil
    @State private var appeared = false

    private var totalKm: Double {
        store.trips.reduce(0) { $0 + $1.distanceKm }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                PageHeader(title: "行程", subtitle: "最近 7 天",
                           badge: "\(store.trips.count) 次",
                           badgeOn: !store.trips.isEmpty)

                HStack(spacing: 10) {
                    ValueCard(title: "行程次数", value: String(store.trips.count),
                              unit: "次", symbol: "car.fill")
                    ValueCard(title: "累计里程", value: String(format: "%.1f", totalKm),
                              unit: "km", symbol: "road.lanes")
                }

                if store.tripsLoading {
                    ProgressView().padding(.top, 20)
                } else if !store.tripsError.isEmpty {
                    Text(store.tripsError)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.sub)
                        .padding(.top, 20)
                } else {
                    ForEach(store.trips) { t in
                        TripRow(trip: t)
                            .onTapGesture { selected = t }
                    }
                }

                PrimaryButton(title: "刷新行程") {
                    Task { await store.loadTrips() }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .refreshable {
            // 用独立 Task：避免系统在刷新手势结束时取消这个任务，
            // 否则分段请求会全部被取消，导致列表被刷成空
            let job = Task { await store.loadTrips() }
            await job.value
        }
        .sheet(item: $selected) { t in
            TripDetailView(trip: t)
                .environmentObject(store)
        }
        .onAppear {
            if !appeared {
                appeared = true
                Task { await store.loadTrips() }
            }
        }
    }
}

// MARK: - 行程详情

struct TripDetailView: View {
    @Environment(\.colorScheme) private var scheme
    let trip: Trip
    @EnvironmentObject var store: CarStore
    @State private var speeds: [Double] = []
    @State private var track: [TrackPoint] = []
    @State private var cursor = 0
    @State private var playing = false
    @State private var timer: Timer? = nil
    @State private var loading = true
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    SoftCard {
                        VStack(spacing: 8) {
                            Text("\(trip.start) → \(trip.end)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.ink)
                            Text("\(trip.durationMin) 分钟 · \(String(format: "%.1f", trip.distanceKm)) km")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.sub)
                        }
                    }

                    if !track.isEmpty {
                        SoftCard(padding: 10) {
                            VStack(spacing: 8) {
                                TripMapView(points: track, cursor: cursor, night: scheme == .dark)
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                HStack(spacing: 8) {
                                    Button {
                                        togglePlay()
                                    } label: {
                                        Text(playing ? "⏸ 暂停" : "▶ 回放")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(Capsule().fill(Theme.blue))
                                    }
                                    Slider(value: Binding(
                                        get: { Double(cursor) },
                                        set: { v in
                                            stopPlay()
                                            cursor = min(track.count - 1, max(0, Int(v)))
                                        }
                                    ), in: 0...Double(max(track.count - 1, 1)))
                                    Text(clockText)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(Theme.sub)
                                }

                                HStack(spacing: 8) {
                                    miniStat("车速", value: curSpeed, unit: "km/h")
                                    miniStat("转速", value: curRpm, unit: "rpm")
                                    miniStat("水温", value: curCoolant, unit: "°C")
                                }
                            }
                        }
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ValueCard(title: "平均车速", value: String(format: "%.0f", trip.avgSpeed),
                                  unit: "km/h", symbol: "speedometer")
                        ValueCard(title: "最高车速", value: String(format: "%.0f", trip.maxSpeed),
                                  unit: "km/h", symbol: "arrow.up.right")
                        ValueCard(title: "最高水温", value: String(format: "%.0f", trip.maxCoolant),
                                  unit: "°C", symbol: "thermometer")
                        ValueCard(title: "最低电压", value: String(format: "%.1f", trip.minVoltage),
                                  unit: "V", symbol: "battery.100")
                    }

                    SoftCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("车速曲线")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.ink)
                            if loading {
                                ProgressView()
                            } else {
                                SpeedChart(values: speeds)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("行程详情")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onDisappear { stopPlay() }
        .onAppear {
            loading = true
            Task {
                let d = await store.tripDetail(trip)
                speeds = d.speeds
                track = d.track
                cursor = 0
                loading = false
            }
        }
    }

    // MARK: - 回放

    private var curPoint: TrackPoint? {
        guard !track.isEmpty else { return nil }
        return track[min(cursor, track.count - 1)]
    }
    private var curSpeed: String { curPoint.map { String(format: "%.0f", $0.speed) } ?? "--" }
    private var curRpm: String { curPoint.map { String(format: "%.0f", $0.rpm) } ?? "--" }
    private var curCoolant: String { curPoint.map { String(format: "%.0f", $0.coolant) } ?? "--" }

    private var clockText: String {
        guard let p = curPoint else { return "--:--" }
        let d = Date(timeIntervalSince1970: p.ts / 1000)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func miniStat(_ title: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(Theme.sub)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.ink)
                Text(unit).font(.system(size: 9)).foregroundColor(Theme.sub)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.bgMid))
    }

    private func togglePlay() {
        if playing { stopPlay(); return }
        guard track.count > 1 else { return }
        if cursor >= track.count - 1 { cursor = 0 }
        playing = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            if cursor >= track.count - 1 {
                stopPlay()
            } else {
                cursor += 1
            }
        }
    }

    private func stopPlay() {
        playing = false
        timer?.invalidate()
        timer = nil
    }
}
