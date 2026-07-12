import AppIntents
import Foundation

/// Cálculo de hora de dormir / alarma, reutilizable desde la app y desde Atajos.
enum BedtimeEngine {
    static let token = "BpbEXYlKaUh04zTMydiIzmJ0G32TARTR"

    /// Hora de despertar: antes del primer evento de mañana (−45 min) o 08:00.
    static func recommendedWake() async -> Date {
        API.shared.token = token
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        var wake = cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)!
        if let overview = try? await API.shared.calendar(), let events = overview.events {
            let first = events
                .filter { e in
                    guard let d = Fmt.date(e.start) else { return false }
                    return cal.isDateInTomorrow(d) && (e.start ?? "").contains("T")
                }
                .min { (Fmt.date($0.start) ?? .distantFuture) < (Fmt.date($1.start) ?? .distantFuture) }
            if let ev = first, let s = Fmt.date(ev.start) {
                let cand = s.addingTimeInterval(-45 * 60)
                if cand < wake { wake = cand }
            }
        }
        return wake
    }

    /// Hora de dormir alineada a CICLOS de sueño (~90 min) para despertar al
    /// final de un ciclo (fase ligera). bedtime = wake − latencia − N·ciclo.
    static let cycle: TimeInterval = 90 * 60
    static let latency: TimeInterval = 15 * 60

    static func cyclesFor(need: TimeInterval, recovery: TimeInterval) -> Int {
        max(4, min(6, Int(((need + recovery) / cycle).rounded())))
    }

    static func recommendedBedtime() async -> Date {
        let wake = await recommendedWake()
        let need = UserDefaults.standard.double(forKey: "sleep_need_secs")
        let recovery = UserDefaults.standard.double(forKey: "sleep_recovery_secs")
        let n = cyclesFor(need: need > 0 ? need : 8 * 3600, recovery: recovery)
        return wake.addingTimeInterval(-(latency + Double(n) * cycle))
    }
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
