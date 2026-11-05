import SwiftUI

// MARK: - 数据模型

struct HAState: Decodable {
    let entityId: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state
    }
}

struct CarItem: Identifiable {
    let id: String
    let name: String
    let unit: String
    let symbol: String
}

let carItems: [CarItem] = [
    CarItem(id: "car_speed",      name: "车速",   unit: "km/h", symbol: "speedometer"),
    CarItem(id: "car_rpm",        name: "转速",   unit: "RPM",  symbol: "gauge"),
    CarItem(id: "car_fuel",       name: "油量",   unit: "L",    symbol: "drop.fill"),
    CarItem(id: "car_voltage",    name: "电压",   unit: "V",    symbol: "bolt.fill"),
    CarItem(id: "car_water_temp", name: "水温",   unit: "°C",   symbol: "thermometer"),
    CarItem(id: "car_odometer",   name: "总里程", unit: "km",   symbol: "map")
]

// MARK: - 数据层

@MainActor
final class CarVM: ObservableObject {
    @Published var values: [String: String] = [:]
    @Published var message: String = ""

    private var task: Task<Void, Never>?

    private var base: String {
        (UserDefaults.standard.string(forKey: "base") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var token: String {
        (UserDefaults.standard.string(forKey: "token") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start() {
        stop()
        task = Task { @MainActor in
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func refresh() {
        guard !base.isEmpty, !token.isEmpty else {
            message = "请点右上角「设置」，填 HA 地址和令牌"
            return
        }
        for item in carItems {
            Task { await fetch(item.id) }
        }
    }

    private func fetch(_ key: String) async {
        guard let url = URL(string: base + "/api/states/sensor." + key) else {
            message = "地址格式不对"
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode != 200 {
                message = "HTTP " + String(http.statusCode)
                return
            }
            let st = try JSONDecoder().decode(HAState.self, from: data)
            values[key] = st.state
            message = ""
        } catch {
            message = "连不上服务器"
        }
    }
}

// MARK: - 界面

struct ContentView: View {
    @StateObject private var vm = CarVM()
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            ScrollView {
                if !vm.message.isEmpty {
                    Text(vm.message)
                        .font(.footnote)
                        .foregroundColor(.orange)
                        .padding(.top, 8)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(carItems) { item in
                        CardView(item: item, value: vm.values[item.id] ?? "--")
                    }
                }
                .padding()
            }
            .navigationTitle("车辆数据")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("设置") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

struct CardView: View {
    let item: CarItem
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .foregroundColor(.blue)
                Text(item.name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)

            Text(item.unit)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
}

struct SettingsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @AppStorage("base") private var base: String = ""
    @AppStorage("token") private var token: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Home Assistant 地址")) {
                    TextField("http://你的HA地址:8123", text: $base)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("长期访问令牌")) {
                    TextField("eyJhbGci...", text: $token)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section {
                    Button("保存并关闭") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 入口

@main
struct CarDashApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
