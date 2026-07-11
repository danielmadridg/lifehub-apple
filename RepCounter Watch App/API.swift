import Foundation

// Llamadas a los endpoints del reloj de Life Hub. Autenticadas con el token de
// dispositivo (cabecera X-Device-Token).
enum API {
    private static func request(_ path: String, method: String = "GET",
                                body: [String: Any]? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: Config.baseURL + path)!)
        req.httpMethod = method
        req.setValue(Config.deviceToken, forHTTPHeaderField: "X-Device-Token")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        req.timeoutInterval = 20
        return req
    }

    static func today() async throws -> TodayResponse {
        let (data, _) = try await URLSession.shared.data(for: request("/api/gym/device/today"))
        return try JSONDecoder().decode(TodayResponse.self, from: data)
    }

    static func routines() async throws -> [DeviceRoutine] {
        let (data, _) = try await URLSession.shared.data(for: request("/api/gym/device/routines"))
        return try JSONDecoder().decode([DeviceRoutine].self, from: data)
    }

    static func routine(id: Int) async throws -> TodayResponse {
        let (data, _) = try await URLSession.shared.data(for: request("/api/gym/device/routine/\(id)"))
        return try JSONDecoder().decode(TodayResponse.self, from: data)
    }

    static func logSet(exerciseId: Int, weight: Double, reps: Int) async throws -> SetResult {
        let req = request("/api/gym/device/set", method: "POST",
                          body: ["exercise_id": exerciseId, "weight": weight, "reps": reps])
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(SetResult.self, from: data)
    }

    // ── Hábitos (Bearer: los endpoints normales no usan device token) ────────
    private static func bearerRequest(_ path: String, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: URL(string: Config.baseURL + path)!)
        req.httpMethod = method
        req.setValue("Bearer \(Config.appPassword)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        return req
    }

    static func habitsToday() async throws -> [WatchHabit] {
        let (data, _) = try await URLSession.shared.data(for: bearerRequest("/api/today"))
        return try JSONDecoder().decode([WatchHabit].self, from: data)
    }

    static func markDone(_ id: Int) async throws -> WatchHabit {
        let (data, _) = try await URLSession.shared.data(for: bearerRequest("/api/habits/\(id)/done", method: "POST"))
        return try JSONDecoder().decode(WatchHabit.self, from: data)
    }

    static func undoDone(_ id: Int) async throws -> WatchHabit {
        let (data, _) = try await URLSession.shared.data(for: bearerRequest("/api/habits/\(id)/undo", method: "POST"))
        return try JSONDecoder().decode(WatchHabit.self, from: data)
    }
}
