import SwiftUI

// MARK: - Reading room

struct ReadingRoomView: View {
    let language: Language
    let level: Level
    @Environment(ContentStore.self) private var content

    var body: some View {
        let newIDs = Set((content.featured(language, level, month: .current)?.readings ?? []).map(\.id))
        let readings = content.content(language, level).readings
            .sorted { newIDs.contains($0.id) && !newIDs.contains($1.id) }
        List {
            if readings.isEmpty {
                ContentUnavailableView("No stories yet", systemImage: "book.closed",
                                       description: Text("Download a content pack in Settings to add more."))
            }
            ForEach(readings) { reading in
                NavigationLink {
                    ReadingDetailView(reading: reading, language: language)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(reading.title).font(.headline)
                            if newIDs.contains(reading.id) {
                                Text("NEW").font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.orange, in: Capsule())
                            }
                        }
                        Text(reading.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        Text("\(reading.questions.count) questions").font(.caption).foregroundStyle(.tint)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Reading room · \(level.rawValue)")
    }
}

struct ReadingDetailView: View {
    let reading: Reading
    let language: Language
    @Environment(ProgressStore.self) private var progress
    @State private var result: ExerciseResult?
    @State private var attempt = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ReadingExerciseView(reading: reading, language: language) { r in
                    result = r
                    progress.recordLesson(id: nil, percent: 0, xp: r.points * 10)
                }
                .id(attempt)

                if let result {
                    VStack(spacing: 12) {
                        Label(result.message ?? "", systemImage: result.correct ? "checkmark.seal.fill" : "info.circle.fill")
                            .font(.headline)
                            .foregroundStyle(result.correct ? .green : .orange)
                        Button("Try again") { self.result = nil; attempt += 1 }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.top)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Word bank

struct WordBankView: View {
    let language: Language
    let level: Level
    @Environment(ContentStore.self) private var content
    @State private var search = ""
    @State private var selected: WordInfo?

    var body: some View {
        let words = content.content(language, level).vocab.filter {
            search.isEmpty
                || $0.meaning.localizedCaseInsensitiveContains(search)
                || $0.word.localizedCaseInsensitiveContains(search)
                || Transliterator.latin($0.word, language: language).localizedCaseInsensitiveContains(search)
        }
        List(words) { item in
            HStack {
                Button {
                    selected = content.lookup(item.word, language: language)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        TargetText(text: item.word, language: language, font: .headline)
                        Text(item.meaning).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                SpeakButton(text: item.word, language: language, size: 15)
            }
        }
        .searchable(text: $search, prompt: "Search in English or Latin letters")
        .navigationTitle("Word bank · \(level.rawValue)")
        .sheet(item: $selected) { info in
            WordDetailSheet(info: info).presentationDetents([.medium, .large])
        }
    }
}
