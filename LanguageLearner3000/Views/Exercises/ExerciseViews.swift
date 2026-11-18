import SwiftUI

struct ExerciseResult {
    let correct: Bool
    let points: Int
    let message: String?
}

// MARK: - Multiple choice / listening / gap-fill

struct ChoiceExerciseView: View {
    let question: ChoiceQuestion
    let language: Language
    let onFinish: (ExerciseResult) -> Void
    @State private var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(question.instruction)
                .font(.headline)
                .foregroundStyle(.secondary)

            if question.listening {
                HStack(spacing: 16) {
                    Button {
                        SpeechService.shared.speak(question.audioText ?? question.prompt, language: language)
                    } label: {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                            .frame(width: 96, height: 96)
                            .background(.tint, in: Circle())
                    }
                    .buttonStyle(.plain)
                    SpeakButton(text: question.audioText ?? question.prompt, language: language, slow: true, size: 24)
                    Spacer()
                }
                if selected != nil {
                    TappableText(text: question.prompt, language: language)
                        .transition(.opacity)
                }
            } else if question.promptIsTarget {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        TappableText(text: question.prompt, language: language, font: .title.weight(.semibold))
                        TranslitLine(text: question.prompt, language: language)
                    }
                    Spacer()
                    SpeakButton(text: question.audioText ?? question.prompt, language: language, size: 20)
                }
            } else {
                Text(question.prompt).font(.title.weight(.semibold))
            }

            VStack(spacing: 10) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { idx, option in
                    OptionButton(text: option,
                                 language: question.optionsAreTarget ? language : nil,
                                 state: state(for: idx)) {
                        choose(idx)
                    }
                    .disabled(selected != nil)
                }
            }
        }
        .onAppear {
            if question.listening {
                SpeechService.shared.speak(question.audioText ?? question.prompt, language: language)
            }
        }
    }

    private func state(for idx: Int) -> OptionState {
        guard let selected else { return .idle }
        if idx == question.correctIndex { return .correct }
        if idx == selected { return .wrong }
        return .dimmed
    }

    private func choose(_ idx: Int) {
        withAnimation { selected = idx }
        let correct = idx == question.correctIndex
        // Reinforce pronunciation of the correct target-language answer.
        if question.optionsAreTarget {
            let answer = question.options[question.correctIndex]
            SpeechService.shared.speak(question.audioText ?? answer, language: language)
        } else if question.promptIsTarget, !question.listening {
            SpeechService.shared.speak(question.audioText ?? question.prompt, language: language)
        }
        var message = question.explanation
        if !correct {
            let answer = "Correct answer: \(question.options[question.correctIndex])"
            message = [answer, question.explanation].compactMap { $0 }.joined(separator: "\n")
        }
        onFinish(ExerciseResult(correct: correct, points: correct ? 1 : 0, message: message))
    }
}

/// Small transliteration line respecting the user's setting.
struct TranslitLine: View {
    let text: String
    let language: Language
    @AppStorage("showTranslit") private var showTranslit = true

    var body: some View {
        if showTranslit {
            Text(Transliterator.latin(text.replacingOccurrences(of: "___", with: "…"), language: language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - True / False

struct TrueFalseView: View {
    let word: String
    let shownMeaning: String
    let isTrue: Bool
    let realMeaning: String
    let language: Language
    let onFinish: (ExerciseResult) -> Void
    @State private var answer: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Does this word mean…").font(.headline).foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading) {
                    TappableText(text: word, language: language, font: .largeTitle.bold())
                    TranslitLine(text: word, language: language)
                }
                Spacer()
                SpeakButton(text: word, language: language, size: 22)
            }
            Text("“\(shownMeaning)”?")
                .font(.title2.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
                .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 14) {
                tfButton(true)
                tfButton(false)
            }
        }
        .onAppear { SpeechService.shared.speak(word, language: language) }
    }

    private func tfButton(_ value: Bool) -> some View {
        let color: Color = {
            guard let answer else { return value ? .green : .red }
            if value == isTrue { return .green }
            return answer == value ? .red : .gray
        }()
        return Button {
            answer = value
            let correct = value == isTrue
            onFinish(ExerciseResult(correct: correct, points: correct ? 1 : 0,
                                    message: "\(word) means “\(realMeaning)”"))
        } label: {
            Label(value ? "True" : "False", systemImage: value ? "checkmark" : "xmark")
        }
        .buttonStyle(PrimaryButtonStyle(color: color))
        .disabled(answer != nil)
        .opacity(answer != nil && value != isTrue && answer != value ? 0.4 : 1)
    }
}

// MARK: - Matching pairs

struct MatchingView: View {
    let pairs: [MatchPair]
    let language: Language
    let onFinish: (ExerciseResult) -> Void

    @State private var leftOrder: [MatchPair]
    @State private var rightOrder: [MatchPair]
    @State private var selectedLeft: MatchPair?
    @State private var selectedRight: MatchPair?
    @State private var matched: Set<String> = []
    @State private var wrongFlash: Set<String> = []
    @State private var mistakes = 0

    init(pairs: [MatchPair], language: Language, onFinish: @escaping (ExerciseResult) -> Void) {
        self.pairs = pairs
        self.language = language
        self.onFinish = onFinish
        _leftOrder = State(initialValue: pairs.shuffled())
        _rightOrder = State(initialValue: pairs.shuffled())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Tap a word, then its meaning").font(.headline).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    ForEach(leftOrder) { pair in
                        tile(pair, isLeft: true)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(rightOrder) { pair in
                        tile(pair, isLeft: false)
                    }
                }
            }
        }
    }

    private func tile(_ pair: MatchPair, isLeft: Bool) -> some View {
        let key = (isLeft ? "L" : "R") + pair.id
        let isMatched = matched.contains(pair.id)
        let isSelected = isLeft ? selectedLeft == pair : selectedRight == pair
        let isWrong = wrongFlash.contains(key)
        let color: Color = isMatched ? .green : isWrong ? .red : isSelected ? .accentColor : .secondary

        return Button {
            tap(pair, isLeft: isLeft)
        } label: {
            Group {
                if isLeft {
                    TargetText(text: pair.target, language: language, font: .body.weight(.semibold))
                } else {
                    Text(pair.meaning).font(.subheadline.weight(.medium))
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(6)
            .background(color.opacity(isMatched || isSelected || isWrong ? 0.18 : 0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.6), lineWidth: isSelected ? 2 : 1))
            .opacity(isMatched ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isMatched)
    }

    private func tap(_ pair: MatchPair, isLeft: Bool) {
        if isLeft {
            selectedLeft = pair
            SpeechService.shared.speak(pair.target, language: language)
        } else {
            selectedRight = pair
        }
        guard let l = selectedLeft, let r = selectedRight else { return }
        if l == r {
            withAnimation { _ = matched.insert(l.id) }
            if matched.count == pairs.count {
                let perfect = mistakes == 0
                onFinish(ExerciseResult(correct: perfect, points: perfect ? 1 : 0,
                                        message: perfect ? "All pairs matched!" : "Matched with \(mistakes) mistake\(mistakes == 1 ? "" : "s")."))
            }
        } else {
            mistakes += 1
            let keys: Set<String> = ["L" + l.id, "R" + r.id]
            withAnimation { wrongFlash.formUnion(keys) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation { wrongFlash.subtract(keys) }
            }
        }
        selectedLeft = nil
        selectedRight = nil
    }
}

// MARK: - Sentence builder (tap word tiles, no typing)

struct SentenceBuilderView: View {
    let sentence: Sentence
    let tiles: [String]
    let language: Language
    let onFinish: (ExerciseResult) -> Void

    @State private var chosen: [Int] = []
    @State private var checked: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Tap the words in the right order").font(.headline).foregroundStyle(.secondary)
            Text(sentence.translation).font(.title2.weight(.semibold))

            // Answer area
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(chosen, id: \.self) { idx in
                    tileView(tiles[idx], highlighted: true) {
                        guard checked == nil else { return }
                        withAnimation(.snappy) { chosen.removeAll { $0 == idx } }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(checkedColor.opacity(0.6))
            )

            // Word bank
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { idx, word in
                    tileView(word, highlighted: false) {
                        guard checked == nil else { return }
                        SpeechService.shared.speak(word, language: language)
                        withAnimation(.snappy) { chosen.append(idx) }
                    }
                    .opacity(chosen.contains(idx) ? 0.15 : 1)
                    .disabled(chosen.contains(idx))
                }
            }

            if checked == nil {
                Button("Check") { check() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(chosen.isEmpty)
                    .opacity(chosen.isEmpty ? 0.5 : 1)
            } else {
                HStack(alignment: .top) {
                    TargetText(text: sentence.text, language: language, font: .body.weight(.medium))
                    Spacer()
                    SpeakButton(text: sentence.text, language: language)
                }
            }
        }
    }

    private var checkedColor: Color {
        switch checked {
        case .some(true): .green
        case .some(false): .red
        case .none: .secondary
        }
    }

    private func tileView(_ word: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(word)
                .font(.body.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(highlighted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
        }
        .buttonStyle(.plain)
    }

    private func check() {
        let target = sentence.words.map { SentenceTools.clean($0).lowercased() }
        let attempt = chosen.map { tiles[$0].lowercased() }
        let ok = target == attempt
        withAnimation { checked = ok }
        SpeechService.shared.speak(sentence.text, language: language)
        onFinish(ExerciseResult(correct: ok, points: ok ? 1 : 0, message: ok ? sentence.text : "Correct order: \(sentence.text)"))
    }
}

// MARK: - Reading comprehension

struct ReadingExerciseView: View {
    let reading: Reading
    let language: Language
    let onFinish: (ExerciseResult) -> Void

    @State private var answers: [Int: Int] = [:]
    @State private var submitted = false
    @State private var showTranslation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(reading.title).font(.title2.bold())
                Spacer()
                SpeakButton(text: reading.text, language: language)
                SpeakButton(text: reading.text, language: language, slow: true)
            }
            Label("Tap any word to hear it and see its meaning", systemImage: "hand.tap")
                .font(.caption).foregroundStyle(.secondary)

            TappableText(text: reading.text, language: language, glossary: reading.glossary, font: .title3)
                .padding()
                .background(.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

            DisclosureGroup("Show English translation", isExpanded: $showTranslation) {
                Text(reading.translation).foregroundStyle(.secondary).padding(.top, 6)
            }

            Divider()

            ForEach(Array(reading.questions.enumerated()), id: \.offset) { qi, q in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(qi + 1). \(q.question)").font(.headline)
                    ForEach(Array(q.options.enumerated()), id: \.offset) { oi, option in
                        OptionButton(text: option, language: nil, state: state(q: qi, o: oi, answer: q.answer)) {
                            answers[qi] = oi
                        }
                        .disabled(submitted)
                    }
                }
            }

            if !submitted {
                Button("Check answers") { submit() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(answers.count < reading.questions.count)
                    .opacity(answers.count < reading.questions.count ? 0.5 : 1)
            }
        }
    }

    private func state(q: Int, o: Int, answer: Int) -> OptionState {
        if !submitted { return answers[q] == o ? .selected : .idle }
        if o == answer { return .correct }
        if answers[q] == o { return .wrong }
        return .dimmed
    }

    private func submit() {
        withAnimation { submitted = true }
        let score = reading.questions.enumerated().filter { answers[$0.offset] == $0.element.answer }.count
        onFinish(ExerciseResult(correct: score == reading.questions.count, points: score,
                                message: "\(score) of \(reading.questions.count) questions correct"))
    }
}
