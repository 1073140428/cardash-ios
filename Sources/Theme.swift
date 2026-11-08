import SwiftUI

// MARK: - 颜色

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255.0,
                  green: CGFloat((v >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(v & 0xFF) / 255.0,
                  alpha: 1.0)
    }
}

/// 浅色 / 深色成对定义，随系统 trait 自动切换
func dynColor(_ light: String, _ dark: String) -> Color {
    Color(UIColor { trait in
        UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
    })
}

enum Theme {
    // 文字
    static let ink      = dynColor("111A2B", "EAF1FF")
    static let sub      = dynColor("8792A6", "8FA0BC")
    // 主色
    static let blue     = dynColor("2F6BFF", "4D8BFF")
    static let blueDeep = dynColor("1B4FD8", "2F6BFF")
    static let blueSoft = dynColor("8FC0FF", "6FA8FF")
    // 背景
    static let bgTop    = dynColor("D7E6FB", "0A1020")
    static let bgMid    = dynColor("EDF3FC", "0E1730")
    static let bgEnd    = dynColor("FFFFFF", "090E18")
    // 分隔 / 卡片
    static let line     = dynColor("E4EBF7", "22304A")
    static let card     = dynColor("FFFFFF", "131D31")
    // 状态
    static let good     = dynColor("17A673", "2ED3A0")
    static let warn     = dynColor("F08A24", "FFA53D")
}

// MARK: - 背景

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [Theme.bgTop, Theme.bgMid, Theme.bgEnd]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - 通用卡片

struct SoftCard<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = 20
    let content: Content

    init(padding: CGFloat = 16, radius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.card.opacity(0.92))
            )
            .shadow(color: Theme.blueDeep.opacity(0.07), radius: 14, x: 0, y: 8)
    }
}

struct ValueCard: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    var tint: Color = Theme.blue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.sub)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Theme.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(unit)
                .font(.system(size: 11))
                .foregroundColor(Theme.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.card.opacity(0.92))
        )
        .shadow(color: Theme.blueDeep.opacity(0.06), radius: 10, x: 0, y: 6)
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.blueSoft, Theme.blue],
                                             startPoint: .leading, endPoint: .trailing))
                )
                .shadow(color: Theme.blue.opacity(0.28), radius: 12, x: 0, y: 8)
                .pressable { action() }
    }
}

/// 页面统一头部：大标题 + 右侧状态
struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    var badgeOn: Bool = true

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.ink)
                if let s = subtitle {
                    Text(s)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.sub)
                }
            }
            Spacer()
            if let b = badge {
                Text(b)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(badgeOn ? Theme.blue : Theme.sub)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().stroke(badgeOn ? Theme.blue.opacity(0.6) : Theme.line, lineWidth: 1)
                    )
            }
        }
    }
}

struct CarHero: View {
    var height: CGFloat = 150

    var body: some View {
        Image("car")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
}



// MARK: - 点按动画（按下即触发，不等系统判定）

/// ScrollView 里系统会延迟按压高亮，这里用 DragGesture(minimumDistance: 0)
/// 直接拿触摸按下事件，做到“手指一落就有反馈”。
struct PressableTap: ViewModifier {
    let action: () -> Void
    var scale: CGFloat = 0.92
    var dim: Double = 0.80

    @GestureState private var pressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? scale : 1.0)
            .opacity(pressed ? dim : 1.0)
            .animation(.interpolatingSpring(stiffness: 420, damping: 14), value: pressed)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = true }
                    .onEnded { value in
                        let dx = abs(value.translation.width)
                        let dy = abs(value.translation.height)
                        if dx < 14 && dy < 14 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            action()
                        }
                    }
            )
    }
}

extension View {
    func pressable(scale: CGFloat = 0.92, dim: Double = 0.80,
                   action: @escaping () -> Void) -> some View {
        modifier(PressableTap(action: action, scale: scale, dim: dim))
    }
}

// 旧样式保留（其它地方可能引用），但已不再是主要交互
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.92
    var dim: Double = 0.80
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? dim : 1.0)
            .animation(.interpolatingSpring(stiffness: 380, damping: 13), value: configuration.isPressed)
    }
}
