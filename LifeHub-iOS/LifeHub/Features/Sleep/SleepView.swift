import SwiftUI
import Charts

/// Sueño: panel detallado desde Apple Salud + recomendación de hora de dormir
/// y de alarma según cómo has dormido y tu agenda de mañana.
struct SleepView: View {
    @StateObject private var sleep = SleepManager()
    @State private var tomorrowFirst: CalendarEvent?
    @State private var reminderOn = false

    var body: some View {
        Screen(title: "Sueño", refresh: { await reload() }) {
            if !sleep.loaded {
                SkeletonList()
            } else if sleep.denied {
                Text("Necesito acceso a Salud para leer tu sueño. Actívalo en Ajustes del iPhone → Salud → Life Hub, y lleva el reloj al dormir.")
                    .font(Theme.dSubheadline)
                    .foregroundStyle(Theme.muted)
                    .card()
            } else {
                if let plan = bedtimePlan { recommendationCard(plan) }

                if let n = sleep.lastNight {
                    lastNightPanel(n)
                } else {
                    Text("Sin datos de la última noche. Lleva el Apple Watch puesto al dormir.")
                        .font(Theme.dSubheadline)
                        .foregroundStyle(Theme.muted)
                        .card()
                }

                if sleep.history.count > 1 { trends }
            }
        }
        .task { await reload() }
    }

    func reload() async {
        await sleep.requestAndLoad()
        if let cal = try? await API.shared.calendar() {
            tomorrowFirst = firstEventTomorrow(cal.events ?? [])
        }
    }

    // ── Recomendación ─────────────────────────────────────────────────────────

    @ViewBuilder
    func recommendationCard(_ p: BedtimePlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars").font(.system(size: 15, weight: .light)).foregroundStyle(Theme.accent)
                Text("Plan de esta noche").font(Theme.dHeadline).foregroundStyle(Theme.ink)
            }
            HStack(spacing: 10) {
                StatTile(icon: "bed.double", value: hm(p.bedtime), label: "acuéstate")
                StatTile(icon: "alarm", value: hm(p.alarm), label: "alarma")
            }
            Text(p.reason).font(Theme.dCaption).foregroundStyle(Theme.muted)

            HButton(haptic: Haptics.medium) {
                reminderOn.toggle()
                if reminderOn { Notifs.shared.scheduleBedtime(p.bedtime) }
                else { Notifs.shared.cancelBedtime() }
            } label: {
                Label(reminderOn ? "Aviso activado" : "Avísame a la hora de dormir",
                      systemImage: reminderOn ? "bell.fill" : "bell")
                    .font(Theme.dSubheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .secondaryGlass(reminderOn ? Theme.accent : Theme.ink)

            Text("La alarma la pones tú (Apple no deja a otras apps crearla). Aquí tienes la hora exacta.")
                .font(Theme.dCaption2).foregroundStyle(Theme.muted)
        }
        .card()
    }

    struct BedtimePlan { let bedtime: Date; let alarm: Date; let reason: String }

    var bedtimePlan: BedtimePlan? {
        let need: TimeInterval = 8 * 3600
        // Deuda de sueño de las últimas noches (máx 45 min de recuperación).
        let recent = sleep.history.suffix(5)
        let debt = recent.reduce(0.0) { $0 + max(0, need - $1.asleep) }
        let recovery = min(debt * 0.4, 45 * 60)
        let latency: TimeInterval = 15 * 60

        // Despertar: antes del primer evento de mañana (con 45 min de margen),
        // o 08:00 por defecto.
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        var wake = cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)!
        var reasonEvent = "despertar a las 08:00"
        if let ev = tomorrowFirst, let start = Fmt.date(ev.start), hasTime(ev.start) {
            let candidate = start.addingTimeInterval(-45 * 60)
            if candidate < wake { wake = candidate; reasonEvent = "listo para «\(ev.title)»" }
        }
        let bedtime = wake.addingTimeInterval(-(need + recovery + latency))
        let recTxt = recovery > 60 ? " +\(Int(recovery/60)) min de recuperación" : ""
        return BedtimePlan(bedtime: bedtime, alarm: wake,
                           reason: "Objetivo 8 h\(recTxt) · \(reasonEvent)")
    }

    func firstEventTomorrow(_ events: [CalendarEvent]) -> CalendarEvent? {
        let cal = Calendar.current
        return events
            .filter { e in
                guard let d = Fmt.date(e.start) else { return false }
                return cal.isDateInTomorrow(d) && hasTime(e.start)
            }
            .min { (Fmt.date($0.start) ?? .distantFuture) < (Fmt.date($1.start) ?? .distantFuture) }
    }
    func hasTime(_ iso: String?) -> Bool { (iso ?? "").contains("T") }

    // ── Panel de la última noche ──────────────────────────────────────────────

    @ViewBuilder
    func lastNightPanel(_ n: SleepNight) -> some View {
        SectionHeader(title: "Última noche")
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dur(n.asleep)).font(.display(30, weight: .regular)).foregroundStyle(Theme.ink)
                Text("dormido").font(Theme.dCaption).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Int(n.efficiency * 100))%").font(Theme.dHeadline).foregroundStyle(Theme.accent)
                Text("eficiencia").font(Theme.dCaption2).foregroundStyle(Theme.muted)
            }
            StagesBar(n: n)
            HStack {
                stage("Profundo", n.deep, Theme.accent2)
                stage("REM", n.rem, Theme.accent)
                stage("Ligero", n.core, Theme.muted)
                stage("Despierto", n.awake, Theme.bad)
            }
            Text("En cama \(dur(n.inBed)) · \(hm(n.start))–\(hm(n.end))")
                .font(Theme.dCaption).foregroundStyle(Theme.muted)
        }
        .card()

        // Constantes durante el sueño.
        let metrics = nightMetrics(n)
        if !metrics.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(metrics, id: \.0) { m in
                    StatTile(icon: m.2, value: m.1, label: m.0)
                }
            }
        }
    }

    func nightMetrics(_ n: SleepNight) -> [(String, String, String)] {
        var out: [(String, String, String)] = []
        if let v = n.avgHR { out.append(("pulso medio", "\(Int(v)) ppm", "heart")) }
        if let v = n.minHR { out.append(("pulso mínimo", "\(Int(v)) ppm", "heart.circle")) }
        if let v = n.avgHRV { out.append(("HRV media", "\(Int(v)) ms", "waveform.path.ecg")) }
        if let v = n.avgResp { out.append(("respiración", "\(Int(v)) rpm", "lungs")) }
        if let v = n.avgSpO2 { out.append(("oxígeno", "\(Int(v * 100))%", "drop")) }
        if let v = n.wristTemp { out.append(("temp. muñeca", String(format: "%.1f°", v), "thermometer")) }
        return out
    }

    @ViewBuilder
    func stage(_ label: String, _ t: TimeInterval, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(dur(t)).font(Theme.dCaption.weight(.semibold)).foregroundStyle(color)
            Text(label).font(Theme.dCaption2).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // ── Tendencia ─────────────────────────────────────────────────────────────

    @ViewBuilder
    var trends: some View {
        SectionHeader(title: "Últimas noches")
        Chart(sleep.history) { h in
            BarMark(
                x: .value("Día", h.date, unit: .day),
                y: .value("Horas", h.asleep / 3600)
            )
            .foregroundStyle(Theme.accent)
        }
        .frame(height: 160)
        .card()
    }

    // ── Formato ───────────────────────────────────────────────────────────────
    func dur(_ t: TimeInterval) -> String {
        let m = Int(t / 60); return "\(m / 60) h \(m % 60) min"
    }
    func hm(_ d: Date) -> String { d.formatted(.dateTime.hour().minute()) }
}

/// Barra proporcional de fases del sueño.
struct StagesBar: View {
    let n: SleepNight
    var body: some View {
        GeometryReader { geo in
            let total = max(1, n.deep + n.rem + n.core + n.awake)
            HStack(spacing: 2) {
                seg(n.deep, total, geo.size.width, Theme.accent2)
                seg(n.rem, total, geo.size.width, Theme.accent)
                seg(n.core, total, geo.size.width, Theme.muted)
                seg(n.awake, total, geo.size.width, Theme.bad)
            }
        }
        .frame(height: 12)
    }
    @ViewBuilder
    func seg(_ v: Double, _ total: Double, _ w: CGFloat, _ c: Color) -> some View {
        if v > 0 {
            Capsule().fill(c).frame(width: max(2, w * CGFloat(v / total)))
        }
    }
}
