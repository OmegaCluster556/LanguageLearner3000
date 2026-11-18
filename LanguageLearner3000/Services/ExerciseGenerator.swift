import Foundation

/// Deterministic random generator so a given month always produces the same lessons,
/// and a new month produces a different set.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    init(_ parts: String...) {
        // FNV-1a: stable across launches (unlike Swift's hashValue).
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in parts.joined(separator: "|").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Builds lessons out of the content pool. All randomness is seeded by
/// language + level + month, so the set refreshes automatically every month.
struct ExerciseGenerator {
    let language: Language
    let level: Level
    let content: LevelContent
    let allVocab: [VocabItem]
    /// This month's newly written material (if downloaded). It's used first,
    /// so each month's lessons are built mostly from brand-new words and stories.
    var featured: LevelContent? = nil

    static let lessonsPerMonth = 8

    // MARK: Monthly plan

    func monthlyPlan(for month: MonthKey) -> [LessonPlan] {
        var rng = SeededGenerator(language.rawValue, level.rawValue, month.id, "plan")
        var kinds: [LessonKind] = [.vocabulary, .listening, .reading, .grammar, .sentences, .vocabulary, .reading]
        kinds.shuffle(using: &rng)
        // Always start gently with vocabulary and finish with the challenge.
        if let v = kinds.firstIndex(of: .vocabulary) { kinds.swapAt(0, v) }
        kinds.append(.challenge)
        return kinds.enumerated().map { LessonPlan(language: language, level: level, month: month, index: $0.offset, kind: $0.element) }
    }

    func exercises(for plan: LessonPlan) -> [Exercise] {
        var monthRNG = SeededGenerator(language.rawValue, level.rawValue, plan.month.id, "pool")
        var rng = SeededGenerator(plan.id)
        let readingNumber = monthlyPlan(for: plan.month).prefix(plan.index).filter { $0.kind == .reading }.count
        return build(kind: plan.kind, lessonIndex: plan.index, readingIndex: readingNumber, poolRNG: &monthRNG, rng: &rng)
    }

    /// A fresh random lesson every time (not tied to the month).
    func quickPractice() -> [Exercise] {
        var poolRNG = SeededGenerator(seed: UInt64.random(in: 0...UInt64.max))
        var rng = SeededGenerator(seed: UInt64.random(in: 0...UInt64.max))
        let kind = [LessonKind.vocabulary, .listening, .grammar, .sentences].randomElement()!
        var plain = self
        plain.featured = nil // quick practice mixes everything evenly
        return plain.build(kind: .challenge, lessonIndex: Int.random(in: 0..<8), readingIndex: 0, poolRNG: &poolRNG, rng: &rng)
            + plain.build(kind: kind, lessonIndex: 0, readingIndex: 0, poolRNG: &poolRNG, rng: &rng).prefix(3)
    }

    // MARK: Building

    /// Shuffles a pool for this month, putting this month's new items first.
    private func ordered<T>(_ all: [T], _ new: [T], key: (T) -> String, rng: inout SeededGenerator) -> [T] {
        let newKeys = Set(new.map(key))
        return new.shuffled(using: &rng) + all.filter { !newKeys.contains(key($0)) }.shuffled(using: &rng)
    }

    private func build(kind: LessonKind, lessonIndex: Int, readingIndex: Int,
                       poolRNG: inout SeededGenerator, rng: inout SeededGenerator) -> [Exercise] {
        // Month-specific ordering of the pools; each lesson takes a different window.
        let fresh = featured ?? LevelContent()
        let vocab = ordered(content.vocab, fresh.vocab, key: \.word, rng: &poolRNG)
        let sentences = ordered(content.sentences, fresh.sentences, key: \.text, rng: &poolRNG)
        let gaps = ordered(content.gaps, fresh.gaps, key: \.sentence, rng: &poolRNG)
        let readings = ordered(content.readings, fresh.readings, key: \.id, rng: &poolRNG)

        let words = window(vocab, start: lessonIndex * 6, count: 8)
        let sents = window(sentences, start: lessonIndex * 3, count: 6)
        let gapItems = window(gaps, start: lessonIndex * 4, count: 8)
        var out: [Exercise] = []

        switch kind {
        case .vocabulary:
            for w in words.prefix(3) { out.append(meaningQuestion(w, rng: &rng)) }
            out.append(matching(words.shuffled(using: &rng), rng: &rng))
            for w in words.dropFirst(3).prefix(2) { out.append(reverseQuestion(w, rng: &rng)) }
            for w in words.dropFirst(5).prefix(2) { out.append(trueFalse(w, rng: &rng)) }
            if let w = words.last { out.append(listeningWord(w, chooseMeaning: true, rng: &rng)) }

        case .listening:
            for w in words.prefix(4) { out.append(listeningWord(w, chooseMeaning: true, rng: &rng)) }
            for w in words.dropFirst(4).prefix(2) { out.append(listeningWord(w, chooseMeaning: false, rng: &rng)) }
            for s in sents.prefix(3) { out.append(listeningSentence(s, rng: &rng)) }
            out.append(matching(words, rng: &rng))

        case .reading:
            if !readings.isEmpty { out.append(Exercise(kind: .reading(readings[readingIndex % readings.count]))) }
            for w in words.prefix(3) { out.append(meaningQuestion(w, rng: &rng)) }
            if let s = sents.first { out.append(sentenceExercise(s, rng: &rng)) }

        case .grammar:
            for g in gapItems.prefix(6) { out.append(gapQuestion(g, rng: &rng)) }
            for s in sents.prefix(2) { out.append(sentenceExercise(s, rng: &rng)) }

        case .sentences:
            for s in sents.prefix(5) { out.append(sentenceExercise(s, rng: &rng)) }
            for s in sents.dropFirst(5).prefix(1) { out.append(sentenceTranslation(s, rng: &rng)) }
            for w in words.prefix(2) { out.append(reverseQuestion(w, rng: &rng)) }

        case .challenge:
            // A story not used by this month's two reading lessons, if there is one.
            if !readings.isEmpty { out.append(Exercise(kind: .reading(readings[min(2, readings.count - 1)]))) }
            for g in gapItems.prefix(3) { out.append(gapQuestion(g, rng: &rng)) }
            for s in sents.prefix(2) { out.append(sentenceExercise(s, rng: &rng)) }
            for w in words.prefix(2) { out.append(listeningWord(w, chooseMeaning: true, rng: &rng)) }
            out.append(matching(words.reversed(), rng: &rng))
            for w in words.suffix(2) { out.append(trueFalse(w, rng: &rng)) }
        }

        // Fallback if a level has very little content.
        if out.isEmpty {
            for w in vocab.prefix(5) { out.append(meaningQuestion(w, rng: &rng)) }
        }
        return out.filter(isValid)
    }

    private func isValid(_ e: Exercise) -> Bool {
        switch e.kind {
        case .matching(let pairs): pairs.count >= 3
        case .choice(let q): q.options.count >= 2
        default: true
        }
    }

    private func window<T>(_ array: [T], start: Int, count: Int) -> [T] {
        guard !array.isEmpty else { return [] }
        return (0..<min(count, array.count)).map { array[(start + $0) % array.count] }
    }

    // MARK: Distractors

    private func meaningDistractors(for item: VocabItem, count: Int, rng: inout SeededGenerator) -> [String] {
        var pool = content.vocab.map(\.meaning).filter { $0 != item.meaning }
        if pool.count < count { pool += allVocab.map(\.meaning).filter { $0 != item.meaning } }
        return Array(Set(pool)).shuffled(using: &rng).prefix(count).map { $0 }
    }

    private func wordDistractors(for item: VocabItem, count: Int, rng: inout SeededGenerator) -> [String] {
        var pool = content.vocab.map(\.word).filter { $0 != item.word }
        if pool.count < count { pool += allVocab.map(\.word).filter { $0 != item.word } }
        return Array(Set(pool)).shuffled(using: &rng).prefix(count).map { $0 }
    }

    private func shuffledOptions(correct: String, distractors: [String], rng: inout SeededGenerator) -> ([String], Int) {
        let options = ([correct] + distractors).shuffled(using: &rng)
        return (options, options.firstIndex(of: correct) ?? 0)
    }

    // MARK: Exercise factories

    private func meaningQuestion(_ w: VocabItem, rng: inout SeededGenerator) -> Exercise {
        let (opts, idx) = shuffledOptions(correct: w.meaning, distractors: meaningDistractors(for: w, count: 3, rng: &rng), rng: &rng)
        return Exercise(kind: .choice(ChoiceQuestion(
            instruction: "What does this word mean?", prompt: w.word, promptIsTarget: true, listening: false,
            audioText: nil, options: opts, optionsAreTarget: false, correctIndex: idx,
            explanation: w.example.map { "\($0)\n\(w.exampleTranslation ?? "")" })))
    }

    private func reverseQuestion(_ w: VocabItem, rng: inout SeededGenerator) -> Exercise {
        let (opts, idx) = shuffledOptions(correct: w.word, distractors: wordDistractors(for: w, count: 3, rng: &rng), rng: &rng)
        return Exercise(kind: .choice(ChoiceQuestion(
            instruction: "Choose the \(language.displayName) word for:", prompt: w.meaning, promptIsTarget: false, listening: false,
            audioText: nil, options: opts, optionsAreTarget: true, correctIndex: idx,
            explanation: "\(w.word) — \(w.meaning)")))
    }

    private func listeningWord(_ w: VocabItem, chooseMeaning: Bool, rng: inout SeededGenerator) -> Exercise {
        let correct = chooseMeaning ? w.meaning : w.word
        let distractors = chooseMeaning ? meaningDistractors(for: w, count: 3, rng: &rng) : wordDistractors(for: w, count: 3, rng: &rng)
        let (opts, idx) = shuffledOptions(correct: correct, distractors: distractors, rng: &rng)
        return Exercise(kind: .choice(ChoiceQuestion(
            instruction: chooseMeaning ? "Listen and choose the meaning" : "Listen and choose the word you hear",
            prompt: w.word, promptIsTarget: true, listening: true, audioText: w.word,
            options: opts, optionsAreTarget: !chooseMeaning, correctIndex: idx,
            explanation: "\(w.word) — \(w.meaning)")))
    }

    private func listeningSentence(_ s: Sentence, rng: inout SeededGenerator) -> Exercise {
        let others = content.sentences.map(\.translation).filter { $0 != s.translation }.shuffled(using: &rng).prefix(3)
        let (opts, idx) = shuffledOptions(correct: s.translation, distractors: Array(others), rng: &rng)
        return Exercise(kind: .choice(ChoiceQuestion(
            instruction: "Listen to the sentence and choose its meaning", prompt: s.text, promptIsTarget: true,
            listening: true, audioText: s.text, options: opts, optionsAreTarget: false, correctIndex: idx,
            explanation: s.translation)))
    }

    private func sentenceTranslation(_ s: Sentence, rng: inout SeededGenerator) -> Exercise {
        let others = content.sentences.map(\.translation).filter { $0 != s.translation }.shuffled(using: &rng).prefix(3)
        let (opts, idx) = shuffledOptions(correct: s.translation, distractors: Array(others), rng: &rng)
        return Exercise(kind: .choice(ChoiceQuestion(
            instruction: "What does this sentence mean?", prompt: s.text, promptIsTarget: true, listening: false,
            audioText: nil, options: opts, optionsAreTarget: false, correctIndex: idx, explanation: nil)))
    }

    private func gapQuestion(_ g: GapItem, rng: inout SeededGenerator) -> Exercise {
        let (opts, idx) = shuffledOptions(correct: g.answer, distractors: g.distractors, rng: &rng)
        return Exercise(kind: .choice(ChoiceQuestion(
            instruction: "Choose the word that fills the gap", prompt: g.sentence, promptIsTarget: true, listening: false,
            audioText: g.filled, options: opts, optionsAreTarget: true, correctIndex: idx,
            explanation: "\(g.filled)\n\(g.translation)")))
    }

    private func matching(_ words: [VocabItem], rng: inout SeededGenerator) -> Exercise {
        var seen = Set<String>()
        let unique = words.filter { seen.insert($0.meaning).inserted }
        let pairs = unique.prefix(5).map { MatchPair(target: $0.word, meaning: $0.meaning) }
        return Exercise(kind: .matching(pairs))
    }

    private func trueFalse(_ w: VocabItem, rng: inout SeededGenerator) -> Exercise {
        let isTrue = Bool.random(using: &rng)
        let shown = isTrue ? w.meaning : (meaningDistractors(for: w, count: 1, rng: &rng).first ?? w.meaning)
        return Exercise(kind: .trueFalse(word: w.word, shownMeaning: shown, isTrue: shown == w.meaning, realMeaning: w.meaning))
    }

    /// Sentence builder for shorter sentences, translation choice for long ones.
    private func sentenceExercise(_ s: Sentence, rng: inout SeededGenerator) -> Exercise {
        let words = s.words.map(SentenceTools.clean)
        guard words.count <= 10 else { return sentenceTranslation(s, rng: &rng) }
        let lowered = Set(words.map { $0.lowercased() })
        let extra = content.sentences
            .flatMap { $0.words.map(SentenceTools.clean) }
            .filter { !lowered.contains($0.lowercased()) && !$0.isEmpty }
        let distractors = Array(Set(extra)).shuffled(using: &rng).prefix(words.count > 6 ? 2 : 3)
        let tiles = (words + distractors).shuffled(using: &rng)
        return Exercise(kind: .sentenceBuilder(s, tiles: tiles))
    }
}

enum SentenceTools {
    /// Strips surrounding punctuation from a word tile (keeps inner hyphens/apostrophes).
    static func clean(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:«»\"“”()—–…"))
    }
}
