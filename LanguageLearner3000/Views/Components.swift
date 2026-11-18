import SwiftUI

// MARK: - Speaker button

struct SpeakButton: View {
    let text: String
    let language: Language
    var slow = false
    var size: CGFloat = 18

    var body: some View {
        Button {
            SpeechService.shared.speak(text, language: language, slow: slow)
        } label: {
            Image(systemName: slow ? "tortoise.fill" : "speaker.wave.2.fill")
                .font(.system(size: size, weight: .semibold))
                .padding(10)
                .background(.tint.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityLabel(slow ? "Play slowly" : "Play pronunciation")
    }
}

// MARK: - Cyrillic text with optional transliteration

struct TargetText: View {
    let text: String
    let language: Language
    var font: Font = .body
    @AppStorage("showTranslit") private var showTranslit = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(font)
            if showTranslit {
                Text(Transliterator.latin(text, language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Flow layout (wrapping row of views)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Tappable text: tap any word for audio + definition

struct TappableText: View {
    let text: String
    let language: Language
    var glossary: [String: String]? = nil
    var font: Font = .title3
    @Environment(ContentStore.self) private var content
    @State private var selected: WordInfo?

    private var tokens: [(Int, String)] {
        text.split(separator: " ", omittingEmptySubsequences: true).map(String.init).enumerated().map { ($0.offset, $0.element) }
    }

    var body: some View {
        FlowLayout(spacing: 5, lineSpacing: 8) {
            ForEach(tokens, id: \.0) { _, token in
                if token.contains("___") {
                    Text(token.replacingOccurrences(of: "___", with: " ____ "))
                        .font(font.weight(.bold))
                        .foregroundStyle(.tint)
                } else {
                    Text(token)
                        .font(font)
                        .padding(.vertical, 2)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(.tint.opacity(0.35)).frame(height: 1.5).offset(y: 1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let info = content.lookup(token, language: language, glossary: glossary)
                            SpeechService.shared.speak(info.tapped, language: language)
                            selected = info
                        }
                }
            }
        }
        .sheet(item: $selected) { info in
            WordDetailSheet(info: info)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Word detail sheet

struct WordDetailSheet: View {
    let info: WordInfo
    @Environment(\.dismiss) private var dismiss

    private var wiktionaryURL: URL? {
        let term = (info.headword ?? info.tapped).lowercased()
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://en.wiktionary.org/wiki/\(encoded)#\(info.language.wiktionarySection)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 14) {
                        TargetText(text: info.tapped, language: info.language, font: .largeTitle.bold())
                        Spacer()
                        SpeakButton(text: info.tapped, language: info.language, size: 22)
                        SpeakButton(text: info.tapped, language: info.language, slow: true, size: 22)
                    }

                    if let meaning = info.meaning {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Definition", systemImage: "text.book.closed.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(meaning).font(.title3.weight(.medium))
                            if let head = info.headword, head.lowercased() != info.tapped.lowercased() {
                                HStack(spacing: 6) {
                                    Text(info.approximate ? "Probably a form of" : "Form of")
                                    Text(head).bold()
                                    SpeakButton(text: head, language: info.language, size: 12)
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                            if let level = info.level {
                                Text(level.rawValue)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(level.color.opacity(0.2), in: Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        Text("This word isn't in the course dictionary yet. You can still listen to it above, or look it up below.")
                            .foregroundStyle(.secondary)
                    }

                    if let example = info.example {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Example", systemImage: "quote.opening")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            HStack(alignment: .top) {
                                TargetText(text: example, language: info.language, font: .body)
                                Spacer()
                                SpeakButton(text: example, language: info.language, size: 14)
                            }
                            if let t = info.exampleTranslation { Text(t).italic().foregroundStyle(.secondary) }
                        }
                        .padding()
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    }

                    if let url = wiktionaryURL {
                        Link(destination: url) {
                            Label("Full entry on Wiktionary", systemImage: "safari")
                        }
                    }
                }
                .padding()
            }
            .tint(info.language.tint)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Answer option button

enum OptionState { case idle, selected, correct, wrong, dimmed }

struct OptionButton: View {
    let text: String
    let language: Language?
    let state: OptionState
    let action: () -> Void

    private var color: Color {
        switch state {
        case .correct: .green
        case .wrong: .red
        case .selected: .accentColor
        default: .secondary
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                if let language {
                    TargetText(text: text, language: language, font: .body.weight(.medium))
                } else {
                    Text(text).font(.body.weight(.medium))
                }
                Spacer()
                if state == .correct { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                if state == .wrong { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(state == .idle || state == .dimmed ? 0.06 : 0.15), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(state == .idle ? 0.25 : 0.8), lineWidth: state == .idle ? 1 : 2))
            .opacity(state == .dimmed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Primary button style

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = .accentColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}
