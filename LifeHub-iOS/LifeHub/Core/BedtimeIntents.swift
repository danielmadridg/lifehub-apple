import AppIntents
import Foundation

/// Cálculo de hora de dormir / alarma, reutilizable desde la app y desde Atajos.
enum BedtimeEngine {
    static let token = "BpbEXYlKaUh04zTMydiIzmJ0G32TARTR"
    static let latency: TimeInterval = 15 * 60

    /// Plan de sueño con ciencia personalizada (ciclo real, deuda+recuperación,
    /// cronotipo). Alinea la alarma al final de un ciclo (fase ligera).
    static func plan() async -> (wake: Date, bed: Date) {
        API.shared.token = token
        let ud = UserDefaults.standard
        let cycle = ud.double(forKey: "sleep_cycle_secs") > 0 ? ud.double(forKey: "sleep_cycle_secs") : 90 * 60
        let need = ud.double(forKey: "sleep_need_secs") > 0 ? ud.double(forKey: "sleep_need_secs") : 8 * 3600
        let recovery = ud.double(forKey: "sleep_recovery_secs") + ud.double(forKey: "sleep_recovery_extra_secs")
        let n = max(4, min(6, Int(((need + recovery) / cycle).rounded())))

        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        // Base: ritmo natural (cronotipo) o 08:00.
        var wake = cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)!
        let midH = ud.double(forKey: "sleep_mid_h")
        if midH > 0 {
            let clk = midH.truncatingRemainder(dividingBy: 24)
            if let mid = cal.date(bySettingHour: Int(clk), minute: Int((clk - floor(clk)) * 60), second: 0, of: tomorrow) {
                wake = mid.addingTimeInterval(Double(n) * cycle / 2)
            }
        }
        // El primer evento de mañana manda si es más temprano.
        if let events = (try? await API.shared.calendar())?.events {
            if let ev = events.filter({ e in
                    guard let d = Fmt.date(e.start) else { return false }
                    return cal.isDateInTomorrow(d) && (e.start ?? "").contains("T")
                }).min(by: { (Fmt.date($0.start) ?? .distantFuture) < (Fmt.date($1.start) ?? .distantFuture) }),
               let s = Fmt.date(ev.start), s.addingTimeInterval(-45 * 60) < wake {
                wake = s.addingTimeInterval(-45 * 60)
            }
        }
        return (wake, wake.addingTimeInterval(-(latency + Double(n) * cycle)))
    }

    static func recommendedWake() async -> Date { await plan().wake }
    static func recommendedBedtime() async -> Date { await plan().bed }
}

/// Atajo: devuelve la hora de alarma recomendada (para encadenar con "Crear alarma").
struct RecommendedAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Hora de alarma recomendada"
    static var description = IntentDescription("Calcula a qué hora poner la alarma según tu agenda de mañana y tu objetivo de sueño.")

    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let alarm = await BedtimeEngine.recommendedWake()
        let hm = alarm.formatted(.dateTime.hour().minute())
        return .result(value: alarm, dialog: "Pon la alarma a las \(hm).")
    }
}

/// Atajo: devuelve la hora de dormir recomendada.
struct RecommendedBedtimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Hora de dormir recomendada"
    static var description = IntentDescription("Calcula a qué hora acostarte para llegar a tu objetivo de sueño.")

    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let bedtime = await BedtimeEngine.recommendedBedtime()
        let hm = bedtime.formatted(.dateTime.hour().minute())
        return .result(value: bedtime, dialog: "Acuéstate a las \(hm).")
    }
}

struct LifeHubShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecommendedAlarmIntent(),
                    phrases: ["Hora de alarma de \(.applicationName)"],
                    shortTitle: "Alarma recomendada",
                    systemImageName: "alarm")
        AppShortcut(intent: RecommendedBedtimeIntent(),
                    phrases: ["Hora de dormir de \(.applicationName)"],
                    shortTitle: "Hora de dormir",
                    systemImageName: "moon.stars")
    }
}
