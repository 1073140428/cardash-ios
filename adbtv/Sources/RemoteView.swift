import SwiftUI
import UIKit

/// 把显示区域里的点击坐标换算成设备物理像素
enum ScreenMapper {
    static func map(_ p: CGPoint, in size: CGSize, image: UIImage, screen: CGSize) -> CGPoint {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0, size.width > 0, size.height > 0 else { return .zero }
        let scale = min(size.width / imgSize.width, size.height / imgSize.height)
        let dw = imgSize.width * scale
        let dh = imgSize.height * scale
        let ox = (size.width - dw) / 2
        let oy = (size.height - dh) / 2
        let x = (p.x - ox) / scale
        let y = (p.y - oy) / scale
        let kx = screen.width / imgSize.width
        let ky = screen.height / imgSize.height
        return CGPoint(x: max(0, min(screen.width, x * kx)),
                       y: max(0, min(screen.height, y * ky)))
    }
}

struct RemoteView: View {
    @EnvironmentObject var adb: ADBService

    @AppStorage("screenInterval") private var interval: Double = 1.2
    @AppStorage("refreshOnKey") private var refreshOnKey: Bool = true

    @State private var image: UIImage?
    @State private var paused = false
    @State private var loading = false
    @State private var loopTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var showFullScreen = false

    private var aspect: CGFloat {
        guard let img = image, img.size.height > 0 else { return 16.0 / 9.0 }
        return img.size.width / img.size.height
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            screenCard
            quickBar
            Spacer(minLength: 4)
            keypad
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { startLoop() }
        .onDisappear { stopLoop() }
        .onChange(of: adb.isConnected) { connected in
            if connected { startLoop() } else { stopLoop(); image = nil }
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenRemote(image: $image, isPresented: $showFullScreen)
                .environmentObject(adb)
        }
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.deepBlue.opacity(0.9)))
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 8) {
            Text("投屏遥控")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(Theme.textMain)
            Spacer()
            iconButton("arrow.up.left.and.arrow.down.right") {
                guard image != nil else { show("还没有画面"); return }
                showFullScreen = true
            }
            iconButton("camera") {
                Task { await saveShot() }
            }
        }
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.primaryDeep)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white))
                .overlay(Circle().stroke(Theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: 画面（按宽度撑满，无黑边）

    private var screenCard: some View {
        Group {
            if let img = image {
                GeometryReader { geo in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Color.black)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { v in
                                    handleGesture(start: v.startLocation, end: v.location, in: geo.size, img: img)
                                }
                        )
                }
                .aspectRatio(aspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(0.3), lineWidth: 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    Text("点画面可操作电视")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.4)))
                        .padding(7)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.primarySoft)
                    VStack(spacing: 8) {
                        Image(systemName: adb.isConnected ? "display" : "wifi.slash")
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(Theme.textFaint)
                        Text(adb.isConnected ? (loading ? "正在获取画面…" : "暂无画面") : "连接后显示电视画面")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textSub)
                    }
                }
                .aspectRatio(aspect, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            if adb.isConnected {
                Text(paused ? "已暂停" : String(format: "%.1fs", interval))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(7)
            }
        }
    }

    // MARK: 快捷栏

    private var quickBar: some View {
        HStack(spacing: 8) {
            smallButton("刷新", "arrow.triangle.2.circlepath") {
                Task { await refresh() }
            }
            smallButton(paused ? "继续" : "暂停", paused ? "play.fill" : "pause.fill") {
                paused.toggle()
                if !paused { startLoop() } else { stopLoop() }
            }
            smallButton("剪贴板", "doc.on.clipboard") {
                let text = UIPasteboard.general.string ?? ""
                Task {
                    await adb.sendText(text)
                    show(text.isEmpty ? "剪贴板为空" : "已同步剪贴板")
                }
            }
            smallButton("全屏", "arrow.up.left.and.arrow.down.right") {
                guard image != nil else { show("还没有画面"); return }
                showFullScreen = true
            }
        }
        .disabled(!adb.isConnected)
        .opacity(adb.isConnected ? 1 : 0.45)
    }

    private func smallButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Theme.deepBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: 遥控盘

    private var keypad: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                key("返回", 4)
                key("主页", 3)
                key("菜单", 82)
            }

            HStack(spacing: 10) {
                VStack(spacing: 10) {
                    key("↑", 19)
                    HStack(spacing: 10) {
                        key("←", 21)
                        key("OK", 66, highlight: true)
                        key("→", 22)
                    }
                    key("↓", 20)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    key("音量+", 24)
                    key("静音", 164)
                    key("音量-", 25)
                }
                .frame(width: 96)
            }

            HStack(spacing: 10) {
                key("电源", 26)
                key("上个应用", 187)
                key("输入源", 172)
            }
        }
        .disabled(!adb.isConnected)
        .opacity(adb.isConnected ? 1 : 0.45)
    }

    private func key(_ title: String, _ code: Int, highlight: Bool = false) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                await adb.key(code)
                if refreshOnKey && !paused { await sleepRefresh() }
            }
        } label: {
            Text(title)
        }
        .buttonStyle(KeyPadStyle(highlight: highlight))
    }

    // MARK: 画面交互

    private func handleGesture(start: CGPoint, end: CGPoint, in size: CGSize, img: UIImage) {
        guard adb.isConnected else { return }
        let a = ScreenMapper.map(start, in: size, image: img, screen: adb.screenSize)
        let b = ScreenMapper.map(end, in: size, image: img, screen: adb.screenSize)
        let dist = hypot(end.x - start.x, end.y - start.y)

        Task {
            if dist < 12 {
                await adb.tap(x: Int(a.x), y: Int(a.y))
            } else {
                await adb.swipe(from: a, to: b, ms: 240)
            }
            if refreshOnKey && !paused { await sleepRefresh() }
        }
    }

    // MARK: 拉流循环

    private func startLoop() {
        stopLoop()
        guard adb.isConnected, !paused else { return }
        loopTask = Task {
            while !Task.isCancelled {
                await refresh()
                let ns = UInt64(max(0.4, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func refresh() async {
        guard adb.isConnected, !loading else { return }
        loading = true
        let img = await adb.screenshot()
        if let img { image = img }
        loading = false
    }

    private func sleepRefresh() async {
        try? await Task.sleep(nanoseconds: 180_000_000)
        await refresh()
    }

    private func saveShot() async {
        var shot = image
        if shot == nil { shot = await adb.screenshot() }
        guard let img = shot else { show("截图失败"); return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        show("已保存到相册")
    }

    private func show(_ t: String) {
        withAnimation { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { if toast == t { toast = nil } }
        }
    }
}

// MARK: - 全屏投屏 + 悬浮遥控

struct FullScreenRemote: View {
    @EnvironmentObject var adb: ADBService
    @Binding var image: UIImage?
    @Binding var isPresented: Bool

    @AppStorage("screenInterval") private var interval: Double = 1.2
    @AppStorage("refreshOnKey") private var refreshOnKey: Bool = true

    @State private var padOffset: CGSize = .zero

    private var aspect: CGFloat {
        guard let img = image, img.size.height > 0 else { return 16.0 / 9.0 }
        return img.size.width / img.size.height
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let img = image {
                GeometryReader { geo in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { v in
                                    let a = ScreenMapper.map(v.startLocation, in: geo.size, image: img, screen: adb.screenSize)
                                    let b = ScreenMapper.map(v.location, in: geo.size, image: img, screen: adb.screenSize)
                                    let dist = hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y)
                                    Task {
                                        if dist < 12 {
                                            await adb.tap(x: Int(a.x), y: Int(a.y))
                                        } else {
                                            await adb.swipe(from: a, to: b, ms: 240)
                                        }
                                        if refreshOnKey { await poke() }
                                    }
                                }
                        )
                }
                .aspectRatio(aspect, contentMode: .fit)
            } else {
                ProgressView().tint(.white)
            }

            // 关闭按钮
            VStack {
                HStack {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }

            // 悬浮遥控盘
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    floatingPad
                        .offset(padOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    padOffset = CGSize(
                                        width: padOffset.width + v.translation.width * 0.06,
                                        height: padOffset.height + v.translation.height * 0.06
                                    )
                                }
                        )
                }
                .padding(.trailing, 12)
                .padding(.bottom, 24)
            }
        }
        .statusBarHidden(true)
    }

    private var floatingPad: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                fkey("音量-", 25)
                fkey("静音", 164)
                fkey("音量+", 24)
            }
            HStack(spacing: 8) {
                fkey("←", 21)
                fkey("OK", 66, big: true)
                fkey("→", 22)
            }
            HStack(spacing: 8) {
                fkey("返回", 4)
                fkey("↑", 19)
                fkey("主页", 3)
            }
            HStack(spacing: 8) {
                fkey("↓", 20)
                fkey("菜单", 82)
                fkey("电源", 26)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .opacity(0.92)
    }

    private func fkey(_ title: String, _ code: Int, big: Bool = false) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                await adb.key(code)
                if refreshOnKey { await poke() }
            }
        } label: {
            Text(title)
                .font(.system(size: big ? 15 : 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: big ? 58 : 46, height: big ? 46 : 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(big ? 0.28 : 0.14))
                )
        }
        .buttonStyle(.plain)
    }

    private func poke() async {
        try? await Task.sleep(nanoseconds: 200_000_000)
        if let img = await adb.screenshot() { image = img }
    }
}
