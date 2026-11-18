import SwiftUI

/// A running lesson: a list of exercises plus the lesson it belongs to (if any).
struct LessonSession: Identifiable {
    let id = UUID()
    let title: String
    let language: Language
    let planID: String?
    let exercises: [Exercise]
}

struct LessonView: View {
    let session: LessonSession
    @Environment(\.dismiss) private var dismiss
    @Environment(ProgressStore.self) private var progress

    @State private var index = 0
    @State private var points = 0
    @State private var result: ExerciseResult?
    @State private var finished = false
    @State private var confirmQuit = false

    private var maxPoints: Int { session.exercises.reduce(0) { $0 + $1.maxPoints } }
    private var percent: Int { maxPoints == 0 ? 0 : Int((Double(points) / Double(maxPoints) * 100).rounded()) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if finished {
                summary
            } else if session.exercises.indices.contains(index) {
                ScrollView {
                    exerciseView(session.exercises[index])
                        .id(session.exercises[index].id)
                        .padding(20)
                        .padding(.bottom, 140)
                }
                .scrollDismissesKeyboard(.immediately)
                .overlay(alignment: .bottom) { feedbackBar }
            }
        }
        .tint(session.language.tint)
        .confirmationDialog("Quit this lesson?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Quit", role: .destructive) { SpeechService.shared.stop(); dismiss() }
        } message: {
            Text("Your progress in this lesson won't be saved.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                if finished || index == 0 && result == nil { dismiss() } else { confirmQuit = true }
            } label: {
                Image(systemName: "xmark").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(index + (result == nil ? 0 : 1)), total: Double(max(session.exercises.count, 1)))
                .progressViewStyle(.linear)
                .tint(.green)
                .scaleEffect(x: 1, y: 2.2)
            Label("\(points)", systemImage: "star.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Exercise

    @ViewBuilder
    private func exerciseView(_ exercise: Exercise) -> some View {
        let lang = session.language
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
            switch exercise.kind {
            case .choice(let q):
                ChoiceExerciseView(question: q, language: lang, onFinish: handle)
            case .matching(let pairs):
                MatchingView(pairs: pairs, language: lang, onFinish: handle)
            case .sentenceBuilder(let s, let tiles):
                SentenceBuilderView(sentence: s, tiles: tiles, language: lang, onFinish: handle)
            case .reading(let r):
                ReadingExerciseView(reading: r, language: lang, onFinish: handle)
            case .trueFalse(let word, let shown, let isTrue, let real):
                TrueFalseView(word: word, shownMeaning: shown, isTrue: isTrue, realMeaning: real, language: lang, onFinish: handle)
            }
        }
    }

    private func handle(_ r: ExerciseResult) {
        points += r.points
        withAnimation(.spring(duration: 0.35)) { result = r }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(r.correct ? .success : .error)
    }

    // MARK: Feedback bar

    @ViewBuilder
    private var feedbackBar: some View {
        if let result {
            VStack(alignment: .leading, spacing: 10) {
                Label(result.correct ? "Great job!" : "Not quite", systemImage: result.correct ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(result.correct ? .green : .orange)
                if let message = result.message, !message.isEmpty {
                    Text(message).font(.subheadline).foregroundStyle(.primary.opacity(0.8))
                }
                Button(index + 1 < session.exercises.count ? "Continue" : "See results") { next() }
                    .buttonStyle(PrimaryButtonStyle(color: result.correct ? .green : .orange))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func next() {
        SpeechService.shared.stop()
        if index + 1 < session.exercises.count {
            withAnimation { result = nil; index += 1 }
        } else {
            progress.recordLesson(id: session.planID, percent: percent, xp: points * 10)
            withAnimation { result = nil; finished = true }
        }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(percent >= 90 ? "🏆" : percent >= 60 ? "🎉" : "💪").font(.system(size: 80))
            Text(percent >= 90 ? "Outstanding!" : percent >= 60 ? "Lesson complete!" : "Keep practicing!")
                .font(.largeTitle.bold())
            HStack(spacing: 16) {
                statTile("\(percent)%", "Score", "target", .blue)
                statTile("+\(points * 10)", "XP", "star.fill", .orange)
                statTile("\(progress.currentStreak)", "Day streak", "flame.fill", .red)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
    }

    private func statTile(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}
