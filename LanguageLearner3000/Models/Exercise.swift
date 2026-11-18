import Foundation

/// A multiple-choice question. Used for translation, listening, gap-fill, etc.
struct ChoiceQuestion: Hashable {
    /// Small label shown above the prompt, e.g. "Translate this word".
    let instruction: String
    /// The prompt text. May be in the target language or English.
    let prompt: String
    /// True when `prompt` is in Russian/Ukrainian (tappable + speakable).
    let promptIsTarget: Bool
    /// Listening mode: prompt is hidden until answered and auto-plays.
    let listening: Bool
    /// Text to speak for the speaker button (defaults to prompt).
    let audioText: String?
    let options: [String]
    let optionsAreTarget: Bool
    let correctIndex: Int
    /// Shown after answering (e.g. full translation).
    let explanation: String?
}

struct MatchPair: Hashable, Identifiable {
    let target: String
    let meaning: String
    var id: String { target }
}

enum ExerciseKind: Hashable {
    case choice(ChoiceQuestion)
    case matching([MatchPair])
    case sentenceBuilder(Sentence, tiles: [String])
    case reading(Reading)
    case trueFalse(word: String, shownMeaning: String, isTrue: Bool, realMeaning: String)
}

struct Exercise: Identifiable, Hashable {
    let id = UUID()
    let kind: ExerciseKind

    var title: String {
        switch kind {
        case .choice(let q): q.listening ? "Listening" : "Multiple choice"
        case .matching: "Match the pairs"
        case .sentenceBuilder: "Build the sentence"
        case .reading: "Reading comprehension"
        case .trueFalse: "True or false?"
        }
    }

    /// How many points this exercise can award.
    var maxPoints: Int {
        if case .reading(let r) = kind { return r.questions.count }
        return 1
    }
}

// MARK: - Lessons

enum LessonKind: String, CaseIterable, Codable {
    case vocabulary, listening, reading, grammar, sentences, challenge

    var title: String {
        switch self {
        case .vocabulary: "Vocabulary"
        case .listening: "Listening"
        case .reading: "Reading"
        case .grammar: "Grammar in context"
        case .sentences: "Sentence building"
        case .challenge: "Monthly challenge"
        }
    }

    var icon: String {
        switch self {
        case .vocabulary: "rectangle.stack.fill"
        case .listening: "ear.fill"
        case .reading: "book.fill"
        case .grammar: "puzzlepiece.fill"
        case .sentences: "text.word.spacing"
        case .challenge: "trophy.fill"
        }
    }
}

struct LessonPlan: Identifiable, Hashable {
    let language: Language
    let level: Level
    let month: MonthKey
    let index: Int
    let kind: LessonKind

    var id: String { "\(language.rawValue)-\(level.rawValue)-\(month.id)-\(index)" }
    var title: String { "Lesson \(index + 1): \(kind.title)" }
}

/// Identifies a calendar month; the whole exercise set rotates when this changes.
struct MonthKey: Hashable, Codable {
    let year: Int
    let month: Int

    static var current: MonthKey {
        let c = Calendar.current.dateComponents([.year, .month], from: .now)
        return MonthKey(year: c.year ?? 2026, month: c.month ?? 1)
    }

    var id: String { String(format: "%04d-%02d", year, month) }

    var displayName: String {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = 1
        let date = Calendar.current.date(from: comps) ?? .now
        return date.formatted(.dateTime.month(.wide).year())
    }

    /// Absolute month counter, used to rotate through content in order.
    var ordinal: Int { year * 12 + (month - 1) }

    func adding(months: Int) -> MonthKey {
        let total = ordinal + months
        return MonthKey(year: total / 12, month: total % 12 + 1)
    }

    static var daysUntilNext: Int {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: .now)),
              let next = cal.date(byAdding: .month, value: 1, to: start) else { return 0 }
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: next).day ?? 0)
    }
}
