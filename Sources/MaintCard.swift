import SwiftUI

/// 服务端 /api/maint 返回
struct MaintInfo: Codable {
    var intervalKm: Double = 7500
    var intervalDays: Int = 180
    var lastOdo: Double = 0
    var lastTs: Double = 0
    var curOdo: Double? = nil
    var drivenKm: Double = 0
    var remainKm: Double = 0
    var remainDays: Int = 0
    var daysUsed: Double = 0
    var status: String = "ok"
    var records: [MaintRecord] = []

    enum CodingKeys: String, CodingKey {
        case intervalKm = "interval_km"
        case intervalDays = "interval_days"
        case lastOdo = "last_odo"
        case lastTs = "last_ts"
        case curOdo = "cur_odo"
        case drivenKm = "driven_km"
        case remainKm = "remain_km"
        case remainDays = "remain_days"
        case daysUsed = "days_used"
        case status
        case records
    }

    var ok: Bool { status != "overdue" }
}

struct MaintRecord: Codable, Identifiable {
    var id: Int = 0
    var ts: Double = 0
    var odo: Double = 0
    var note: String = ""
    var date: String? = nil
}

// MARK: - 保养提醒卡片

struct MaintCard: View {
    let info: MaintInfo?

    private var ok: Bool { info?.ok ?? true }

    private var kmText: String {
        guard let m = info else { return "--" }
        if m.remainKm < 0 { return "\(Int(abs(m.remainKm).rounded()))" }
        return "\(Int(m.remainKm.rounded()))"
    }

    private var dayText: String {
        guard let m = info else { return "--" }
        return "\(abs(m.remainDays))"
    }

    private var kmCaption: String {
        guard let m = info else { return "剩余公里" }
        return m.remainKm < 0 ? "已超公里" : "剩余公里"
    }

    private var dayCaption: String {
        guard let m = info else { return "剩余天数" }
        return m.remainDays < 0 ? "已超天数" : "剩余天数"
    }

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.blue)
                    Text("保养提醒")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    MaintCell(big: kmText, unit: "km", caption: kmCaption,
                              ok: ok, tint: Theme.ink)
                    MaintCell(big: dayText, unit: "天", caption: dayCaption,
                              ok: ok, tint: ok ? Theme.blue : Theme.bad)
                }
            }
        }
    }
}

private struct MaintCell: View {
    let big: String
    let unit: String
    let caption: String
    let ok: Bool
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer(minLength: 0)
                Text(ok ? "正常" : "过期")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ok ? Theme.good : Theme.bad)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(big)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.sub)
            }

            Text(caption)
                .font(.system(size: 11))
                .foregroundColor(Theme.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.bgMid.opacity(0.55))
        )
    }
}
