import SwiftUI
import MapKit
import UIKit

// MARK: - 总览

struct OverviewView: View {
    @EnvironmentObject var store: CarStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                PageHeader(
                    title: "总览",
                    subtitle: store.driving ? "行驶中 · \(store.updatedText)" : "已熄火 · \(store.updatedText)",
                    badge: store.connected ? "已连接" : "未连接",
                    badgeOn: store.connected
                )

                SoftCard(padding: 10) {
                    VStack(spacing: 6) {
                        CarHero(height: 126)
                        HStack(spacing: 6) {
                            Text("吉A275CT")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.ink)
                            Text("·")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.sub)
                            Text(store.connected ? "HomeAssistant 已连接" : "等待连接 HomeAssistant")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.sub)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 20)
                    }
                }

                locationCard

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(overviewItems) { item in
                        ValueCard(title: item.name,
                                  value: store.values[item.id] ?? "--",
                                  unit: item.unit,
                                  symbol: item.symbol)
                    }
                }

                if !store.message.isEmpty {
                    Text(store.message)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "F08A24"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    private var overviewItems: [CarItem] {
        let hidden: Set<String> = [
            "obd_throttle", "obd_timing", "obd_maf",
            "obd_load", "obd_map", "obd_speed", "obd_rpm"
        ]
        return carItems.filter { !hidden.contains($0.id) }
    }

    private var locationCard: some View {
        SoftCard(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.blue)
                    Text("车辆位置")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    Spacer()
                    Text(store.driving ? "行驶中" : "停放中")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.sub)
                }

                if store.lat != 0 && store.lon != 0 {
                    Map(
                        coordinateRegion: .constant(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: store.lat, longitude: store.lon),
                            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                        )),
                        annotationItems: [MapPin(lat: store.lat, lon: store.lon)]
                    ) { p in
                        MapMarker(
                            coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon),
                            tint: .blue
                        )
                    }
                    .frame(height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(store.locAddress.isEmpty
                         ? String(format: "%.5f, %.5f", store.lat, store.lon)
                         : store.locAddress)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.sub)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "location.slash")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.sub)
                        Text(store.locStatus.isEmpty ? "等待定位数据（车机未上报坐标）" : store.locStatus)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.sub)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

struct MapPin: Identifiable {
    let id = UUID()
    let lat: Double
    let lon: Double
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var store: CarStore
    @AppStorage("base") private var base: String = ""
    @AppStorage("token") private var token: String = ""
    @State private var saved = false

    private var hostText: String {
        let b = (UserDefaults.standard.string(forKey: "base") ?? "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        let parts = b.split(separator: ":")
        return parts.isEmpty ? "--" : String(parts[0])
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                PageHeader(title: "连接设置",
                           subtitle: "数据来源：Home Assistant")

                CarHero(height: 130)

                SoftCard {
                    VStack(spacing: 14) {
                        HStack {
                            Text("HomeAssistant 连接状态")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.ink)
                            Spacer()
                            Text(store.connected ? "已连接" : "未连接")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(store.connected ? Theme.blue : Theme.sub)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(store.connected ? Theme.blue.opacity(0.12) : Theme.line.opacity(0.6))
                                )
                        }

                        HStack {
                            infoCol("信号强度", store.connected ? "强" : "无")
                            Divider().frame(height: 30)
                            infoCol("服务器", hostText)
                            Divider().frame(height: 30)
                            infoCol("更新频率", "2 s")
                        }
                    }
                }

                SoftCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("服务器地址")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.sub)
                        TextField("http://your-ha:8123", text: $base)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: 15))
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bgMid))

                        Text("长期访问令牌")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.sub)
                        TextField("eyJhbGci...", text: $token)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: 13))
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bgMid))
                    }
                }

                SoftCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("车辆数据")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.ink)
                        Text("车速 / 转速 / 油量 / 电压 / 水温 / 总里程")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.sub)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !store.message.isEmpty {
                    Text(store.message)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "F08A24"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                Button(action: {
                    hideKeyboard()
                    Task { await store.testConnection() }
                }) {
                    Text("测试连接")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.blue.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                PrimaryButton(title: saved ? "已保存" : "保存配置") {
                    hideKeyboard()
                    UserDefaults.standard.set(base.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "base")
                    UserDefaults.standard.set(token.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "token")
                    saved = true
                    Task {
                        await store.refresh()
                        saved = false
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    private func infoCol(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(Theme.sub)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
