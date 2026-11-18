import SwiftUI

struct LanguageHomeView: View {
    let language: Language
    @Environment(ContentStore.self) private var content
    @Environment(ProgressStore.self) private var progress
    @State private var activeSession: LessonSession?

    private var level: Level { progress.level(for: language) }
    private var month: MonthKey { .current }

    private var generator: ExerciseGenerator {
        ExerciseGenerator(language: language, level: level,
                          content: content.content(language, level),
                          allVocab: content.allVocab(language),
                          featured: content.featured(language, level, month: month))
    }

    var body: some View {
        let plans = generator.monthlyPlan(for: month)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerCard
                    levelPicker
                    monthSection(plans)
                    exploreSection
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(language.flag) \(language.displayName)")
        }
        .tint(language.tint)
        .fullScreenCover(item: $activeSession) { session in
            LessonView(session: session)
                .environment(content)
                .environment(progress)
        }
    }

    // MARK: Header

    private var headerCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.nativeName).font(.title2.bold())
                Text("Level \(level.rawValue) · \(level.title)").foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Label("\(progress.currentStreak)", systemImage: "flame.fill").foregroundStyle(.red)
                Label("\(progress.data.xp) XP", systemImage: "star.fill").foregroundStyle(.orange)
            }
            .font(.subheadline.bold())
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: Level picker

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Level").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Level.allCases) { lvl in
                        let selected = lvl == level
                        Button {
                            withAnimation(.snappy) { progress.setLevel(lvl, for: language) }
                        } label: {
                            VStack(spacing: 2) {
                                Text(lvl.rawValue).font(.title3.bold())
                                Text(lvl.title).font(.caption2)
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 112, height: 60)
                            .foregroundStyle(selected ? .white : .primary)
                            .background(selected ? lvl.color : Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(lvl.color.opacity(selected ? 0 : 0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Monthly lessons

    private func monthSection(_ plans: [LessonPlan]) -> some View {
        let done = progress.completedCount(plans)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(month.displayName) lessons").font(.headline)
                    if let theme = content.theme(language, month: month) {
                        Label("New this month: \(theme)", systemImage: "sparkles")
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    }
                    Text("New set in \(MonthKey.daysUntilNext) day\(MonthKey.daysUntilNext == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(done)/\(plans.count) done").font(.subheadline.bold()).foregroundStyle(.tint)
            }
            ProgressView(value: Double(done), total: Double(max(plans.count, 1))).tint(level.color)

            ForEach(plans) { plan in
                Button {
                    start(plan)
                } label: {
                    lessonRow(plan)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func lessonRow(_ plan: LessonPlan) -> some View {
        let best = progress.bestScore(for: plan.id)
        return HStack(spacing: 14) {
            Image(systemName: plan.kind.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(plan.kind == .challenge ? Color.orange : level.color, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("Lesson \(plan.index + 1)").font(.caption).foregroundStyle(.secondary)
                Text(plan.kind.title).font(.body.weight(.semibold))
            }
            Spacer()
            if let best {
                Label("\(best)%", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(best >= 80 ? .green : .orange)
            } else {
                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.tint)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func start(_ plan: LessonPlan) {
        let exercises = generator.exercises(for: plan)
        activeSession = LessonSession(title: plan.title, language: language, planID: plan.id, exercises: exercises)
    }

    // MARK: Explore

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore").font(.headline)
            Button {
                activeSession = LessonSession(title: "Quick practice", language: language, planID: nil,
                                              exercises: generator.quickPractice())
            } label: {
                exploreRow("Quick practice", "A fresh random mix every time", "bolt.fill", .yellow)
            }
            .buttonStyle(.plain)

            NavigationLink {
                ReadingRoomView(language: language, level: level)
            } label: {
                exploreRow("Reading room", "\(content.content(language, level).readings.count) stories at \(level.rawValue)", "books.vertical.fill", .brown)
            }
            .buttonStyle(.plain)

            NavigationLink {
                WordBankView(language: language, level: level)
            } label: {
                exploreRow("Word bank", "\(content.content(language, level).vocab.count) words with audio", "character.book.closed.fill", .purple)
            }
            .buttonStyle(.plain)
        }
    }

    private func exploreRow(_ title: String, _ subtitle: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
