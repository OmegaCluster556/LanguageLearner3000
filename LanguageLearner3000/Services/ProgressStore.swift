import Foundation
import Observation

/// Saves XP, streak, lesson scores and the chosen level for each language.
@MainActor
@Observable
final class ProgressStore {
    struct Data: Codable {
        var xp = 0
        var streak = 0
        var lastActiveDay: String?
        var bestScores: [String: Int] = [:]      // lesson id -> percent
        var selectedLevels: [String: String] = [:] // language -> level
        var wordsHeard: Int = 0
    }

    private(set) var data: Data
    private let key = "progress.v1"

    init() {
        if let raw = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Data.self, from: raw) {
            data = decoded
        } else {
            data = Data()
        }
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) { UserDefaults.standard.set(raw, forKey: key) }
    }

    func level(for language: Language) -> Level {
        data.selectedLevels[language.rawValue].flatMap(Level.init(rawValue:)) ?? .a1
    }

    func setLevel(_ level: Level, for language: Language) {
        data.selectedLevels[language.rawValue] = level.rawValue
        save()
    }

    func bestScore(for lessonID: String) -> Int? { data.bestScores[lessonID] }

    func completedCount(_ plans: [LessonPlan]) -> Int {
        plans.filter { data.bestScores[$0.id] != nil }.count
    }

    func recordLesson(id: String?, percent: Int, xp: Int) {
        if let id { data.bestScores[id] = max(percent, data.bestScores[id] ?? 0) }
        data.xp += xp
        touchStreak()
        save()
    }

    private func touchStreak() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: .now)
        guard data.lastActiveDay != today else { return }
        let yesterday = fmt.string(from: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
        data.streak = (data.lastActiveDay == yesterday) ? data.streak + 1 : 1
        data.lastActiveDay = today
    }

    /// Streak shown in the UI (0 if the user missed a day).
    var currentStreak: Int {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: .now)
        let yesterday = fmt.string(from: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
        return (data.lastActiveDay == today || data.lastActiveDay == yesterday) ? data.streak : 0
    }

    func reset() {
        data = Data()
        save()
    }
}
