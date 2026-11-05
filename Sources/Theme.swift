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

enum Theme {
    static let ink      = Color(hex: "111A2B")
    static let sub      = Color(hex: "8792A6")
    static let blue     = Color(hex: "2F6BFF")
    static let blueDeep = Color(hex: "1B4FD8")
    static let blueSoft = Color(hex: "8FC0FF")
    static let bgTop    = Color(hex: "D7E6FB")
    static let bgMid    = Color(hex: "EDF3FC")
    static let line     = Color(hex: "E4EBF7")
    static let good     = Color(hex: "17A673")
}

// MARK: - 背景

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [Theme.bgTop, Theme.bgMid, Color.white]),
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
                    .fill(Color.white.opacity(0.92))
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
                .fill(Color.white.opacity(0.92))
        )
        .shadow(color: Theme.blueDeep.opacity(0.06), radius: 10, x: 0, y: 6)
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        }
        .buttonStyle(PlainButtonStyle())
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
            .scaledToFit()
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
    }
}
