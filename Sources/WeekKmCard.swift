import SwiftUI

/// 近 7 日里程卡片：折线 + 渐变面积 + 数值标签 + 虚线网格（参考「近7日能耗」样式）
struct WeekKmCard: View {
    let days: [DayKm]
    let total: Double
    let avg: Double

    private let teal = Color(hex: "2BD3AE")
    private let tealSoft = Color(hex: "8CEBD9")

    private var maxValue: Double {
        let m = days.map { $0.km }.max() ?? 0
        if m <= 0 { return 10 }
        return max(10, (m / 10).rounded(.up) * 10)
    }

    var body: some View {
        SoftCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("近 7 日里程")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    Spacer()
                    Text(unitText(total))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.sub)
                }

                HStack(spacing: 14) {
                    legendItem(color: teal, dashed: false, text: "每日里程")
                    legendItem(color: tealSoft, dashed: true, text: "日均 \(fmt(avg)) km")
                }

                if days.isEmpty {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.sub.opacity(0.06))
                        .frame(height: 150)
                        .overlay(ProgressView().scaleEffect(0.8))
                } else {
                    GeometryReader { geo in
                        chart(size: geo.size)
                    }
                    .frame(height: 150)
                }

                HStack(spacing: 0) {
                    ForEach(days) { d in
                        Text(d.isToday ? "今天" : d.md.suffix(2).description)
                            .font(.system(size: 10, weight: d.isToday ? .semibold : .regular))
                            .foregroundColor(d.isToday ? teal : Theme.sub)
                            .frame(maxWidth: .infinity)
                    }
                }

                if total <= 0 {
                    Text("近 7 天还没有行程记录")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.sub)
                }
            }
        }
    }

    private func legendItem(color: Color, dashed: Bool, text: String) -> some View {
        HStack(spacing: 5) {
            if dashed {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(color).frame(width: 5, height: 1.6)
                    }
                }
            } else {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(text).font(.system(size: 11)).foregroundColor(Theme.sub)
        }
    }

    private func chart(size: CGSize) -> some View {
        let leftInset: CGFloat = 26
        let padTop: CGFloat = 20      // 顶部数值标签留空间
        let padBottom: CGFloat = 4
        let w = max(1, size.width - leftInset)
        let usableH = max(1, size.height - padTop - padBottom)
        let n = max(days.count, 1)
        let stepX = n > 1 ? w / CGFloat(n - 1) : w / 2
        let maxV = maxValue

        func point(_ i: Int) -> CGPoint {
            let v = days.indices.contains(i) ? days[i].km : 0
            let x = leftInset + (n > 1 ? CGFloat(i) * stepX : w / 2)
            let y = padTop + usableH * (1 - CGFloat(v / maxV))
            return CGPoint(x: x, y: y)
        }

        return ZStack(alignment: .topLeading) {
            // 横向虚线网格 + 左侧刻度
            ForEach(0..<3, id: \.self) { row in
                let v = maxV * Double(2 - row) / 2
                let y = padTop + usableH * (1 - CGFloat(v / maxV))
                Path { p in
                    p.move(to: CGPoint(x: leftInset, y: y))
                    p.addLine(to: CGPoint(x: leftInset + w, y: y))
                }
                .stroke(Theme.sub.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))

                Text("\(Int(v))")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.sub.opacity(0.85))
                    .position(x: leftInset - 12, y: y)
            }

            // 日均虚线
            if avg > 0 {
                let y = padTop + usableH * (1 - CGFloat(min(avg, maxV) / maxV))
                Path { p in
                    p.move(to: CGPoint(x: leftInset, y: y))
                    p.addLine(to: CGPoint(x: leftInset + w, y: y))
                }
                .stroke(tealSoft, style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
            }

            // 面积渐变
            Path { p in
                p.move(to: CGPoint(x: point(0).x, y: padTop + usableH))
                for i in 0..<n { p.addLine(to: point(i)) }
                p.addLine(to: CGPoint(x: point(n - 1).x, y: padTop + usableH))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [teal.opacity(0.34), teal.opacity(0.02)],
                                 startPoint: .top, endPoint: .bottom))

            // 折线
            Path { p in
                p.move(to: point(0))
                for i in 1..<n { p.addLine(to: point(i)) }
            }
            .stroke(teal, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

            // 数据点 + 数值标签
            ForEach(0..<n, id: \.self) { i in
                let pt = point(i)
                Circle()
                    .fill(Theme.card)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(teal, lineWidth: 2))
                    .position(pt)

                let km = days.indices.contains(i) ? days[i].km : 0
                if km > 0 {
                    Text(fmt(km))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.ink)
                        .position(x: pt.x, y: max(8, pt.y - 12))
                }
            }
        }
    }

    private func fmt(_ v: Double) -> String {
        v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    private func unitText(_ v: Double) -> String {
        "共 \(fmt(v)) km"
    }
}
