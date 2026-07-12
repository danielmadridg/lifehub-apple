import Foundation
import HealthKit

/// Resumen de una noche de sueño (derivado de HealthKit).
struct SleepNight {
    var start: Date
    var end: Date
    var inBed: TimeInterval
    var asleep: TimeInterval
    var deep: TimeInterval
    var rem: TimeInterval
    var core: TimeInterval
    var awake: TimeInterval
    var avgHR: Double?
    var minHR: Double?
    var avgHRV: Double?
    var avgResp: Double?
    var wristTemp: Double?
    var avgSpO2: Double?

    var efficiency: Double { inBed > 0 ? min(1, asleep / inBed) : 0 }
}

struct SleepHistoryNight: Identifiable {
    let id = UUID()
    let date: Date       // día en que despertaste
    let asleep: TimeInterval
}

/// Lee sueño y constantes de Apple Salud. Solo lectura.
@MainActor
final class SleepManager: ObservableObject {
    @Published var lastNight: SleepNight?
    @Published var history: [SleepHistoryNight] = []
    @Published var loaded = false
    @Published var denied = false

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!]
        for id: HKQuantityTypeIdentifier in [.heartRate, .heartRateVariabilitySDNN, .respiratoryRate,
                                             .oxygenSaturation, .appleSleepingWristTemperature] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) }
        }
        return s
    }

    func requestAndLoad() async {
        guard HKHealthStore.isHealthDataAvailable() else { denied = true; loaded = true; return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            denied = true
        }
        await load()
    }

    func load() async {
        let now = Date()
        // Última noche: ventana de las últimas 20 h.
        if let samples = try? await sleepSamples(from: now.addingTimeInterval(-20 * 3600), to: now),
           !samples.isEmpty {
            lastNight = await buildNight(samples)
        }
        // Historial: agrupa el sueño de los últimos 8 días por el día de despertar.
        if let samples = try? await sleepSamples(from: now.addingTimeInterval(-8 * 86400), to: now) {
            history = groupHistory(samples)
        }
        loaded = true
    }

    // ── Construcción de la noche ──────────────────────────────────────────────

    private func buildNight(_ samples: [HKCategorySample]) async -> SleepNight {
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        var deep = 0.0, rem = 0.0, core = 0.0, awake = 0.0, asleep = 0.0, inBed = 0.0
        var minStart = Date.distantFuture, maxEnd = Date.distantPast
        for s in samples {
            let dur = s.endDate.timeIntervalSince(s.startDate)
            switch s.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: deep += dur
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: rem += dur
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: core += dur
            case HKCategoryValueSleepAnalysis.awake.rawValue: awake += dur
            case HKCategoryValueSleepAnalysis.inBed.rawValue: inBed += dur
            default: break
            }
            if asleepValues.contains(s.value) {
                asleep += dur
                minStart = min(minStart, s.startDate)
                maxEnd = max(maxEnd, s.endDate)
            }
        }
        let start = minStart == .distantFuture ? (samples.first?.startDate ?? Date()) : minStart
        let end = maxEnd == .distantPast ? (samples.last?.endDate ?? Date()) : maxEnd
        let bed = max(inBed, end.timeIntervalSince(start))

        var n = SleepNight(start: start, end: end, inBed: bed, asleep: asleep,
                           deep: deep, rem: rem, core: core, awake: awake)
        n.avgHR = await stat(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: start, to: end, op: .discreteAverage)
        n.minHR = await stat(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: start, to: end, op: .discreteMin)
        n.avgHRV = await stat(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: start, to: end, op: .discreteAverage)
        n.avgResp = await stat(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), from: start, to: end, op: .discreteAverage)
        n.avgSpO2 = await stat(.oxygenSaturation, unit: .percent(), from: start, to: end, op: .discreteAverage)
        n.wristTemp = await stat(.appleSleepingWristTemperature, unit: .degreeCelsius(), from: start, to: end, op: .discreteAverage)
        return n
    }

    private func groupHistory(_ samples: [HKCategorySample]) -> [SleepHistoryNight] {
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let cal = Calendar.current
        var byDay: [Date: TimeInterval] = [:]
        for s in samples where asleepValues.contains(s.value) {
            let day = cal.startOfDay(for: s.endDate)   // el día en que despiertas
            byDay[day, default: 0] += s.endDate.timeIntervalSince(s.startDate)
        }
        return byDay.map { SleepHistoryNight(date: $0.key, asleep: $0.value) }
            .sorted { $0.date < $1.date }
    }

    // ── Consultas HealthKit envueltas en async ────────────────────────────────

    private func sleepSamples(from: Date, to: Date) async throws -> [HKCategorySample] {
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let pred = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, res, err in
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: (res as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
    }

    private func stat(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date,
                      op: HKStatisticsOptions) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: op) { _, stats, _ in
                let qty = op == .discreteMin ? stats?.minimumQuantity()
                        : op == .discreteMax ? stats?.maximumQuantity()
                        : stats?.averageQuantity()
                cont.resume(returning: qty?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }
}
