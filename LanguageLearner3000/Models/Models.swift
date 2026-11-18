import SwiftUI

// MARK: - Language

enum Language: String, CaseIterable, Identifiable, Codable {
    case russian = "ru"
    case ukrainian = "uk"

    var id: String { rawValue }

    var displayName: String { self == .russian ? "Russian" : "Ukrainian" }
    var nativeName: String { self == .russian ? "Русский" : "Українська" }
    var flag: String { self == .russian ? "🇷🇺" : "🇺🇦" }
    /// BCP-47 code used by the speech synthesizer.
    var speechCode: String { self == .russian ? "ru-RU" : "uk-UA" }
    /// Name of the bundled JSON course file.
    var resourceName: String { self == .russian ? "russian" : "ukrainian" }
    /// Section anchor on en.wiktionary.org.
    var wiktionarySection: String { displayName }

    var tint: Color { self == .russian ? .indigo : .blue }
}

// MARK: - Level

enum Level: String, CaseIterable, Identifiable, Codable {
    case a1 = "A1", a2 = "A2", b1 = "B1", b2 = "B2", c1 = "C1", c2 = "C2"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .a1: "Beginner"
        case .a2: "Elementary"
        case .b1: "Intermediate"
        case .b2: "Upper-Intermediate"
        case .c1: "Advanced"
        case .c2: "Proficient"
        }
    }

    var color: Color {
        switch self {
        case .a1: .green
        case .a2: .mint
        case .b1: .teal
        case .b2: .blue
        case .c1: .purple
        case .c2: .pink
        }
    }
}

// MARK: - Course content (decoded from JSON)

struct VocabItem: Codable, Hashable, Identifiable {
    let word: String
    let meaning: String
    let forms: [String]?
    let example: String?
    let exampleTranslation: String?

    var id: String { word }

    enum CodingKeys: String, CodingKey {
        case word = "w", meaning = "m", forms = "f", example = "e", exampleTranslation = "et"
    }
}

struct Sentence: Codable, Hashable {
    let text: String
    let translation: String

    enum CodingKeys: String, CodingKey { case text = "s", translation = "t" }

    var words: [String] { text.split(separator: " ").map(String.init) }
}

/// A "choose the right word for the gap" item. `sentence` contains `___`.
struct GapItem: Codable, Hashable {
    let sentence: String
    let answer: String
    let distractors: [String]
    let translation: String

    enum CodingKeys: String, CodingKey {
        case sentence = "s", answer = "a", distractors = "o", translation = "t"
    }

    var filled: String { sentence.replacingOccurrences(of: "___", with: answer) }
}

struct ReadingQuestion: Codable, Hashable {
    let question: String
    let options: [String]
    let answer: Int

    enum CodingKeys: String, CodingKey { case question = "q", options = "o", answer = "a" }
}

struct Reading: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let text: String
    let translation: String
    let glossary: [String: String]?
    let questions: [ReadingQuestion]
}

struct LevelContent: Codable {
    var vocab: [VocabItem] = []
    var sentences: [Sentence] = []
    var gaps: [GapItem] = []
    var readings: [Reading] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vocab = try c.decodeIfPresent([VocabItem].self, forKey: .vocab) ?? []
        sentences = try c.decodeIfPresent([Sentence].self, forKey: .sentences) ?? []
        gaps = try c.decodeIfPresent([GapItem].self, forKey: .gaps) ?? []
        readings = try c.decodeIfPresent([Reading].self, forKey: .readings) ?? []
    }

    /// Adds anything from `other` that isn't already present.
    mutating func merge(_ other: LevelContent) {
        let words = Set(vocab.map(\.word))
        vocab += other.vocab.filter { !words.contains($0.word) }
        let sents = Set(sentences.map(\.text))
        sentences += other.sentences.filter { !sents.contains($0.text) }
        let gapSet = Set(gaps.map(\.sentence))
        gaps += other.gaps.filter { !gapSet.contains($0.sentence) }
        let ids = Set(readings.map(\.id))
        readings += other.readings.filter { !ids.contains($0.id) }
    }
}

struct CoursePack: Codable {
    var version: String?
    /// Monthly packs have a theme, e.g. "holidays and traditions".
    var theme: String?
    var levels: [String: LevelContent]
}
