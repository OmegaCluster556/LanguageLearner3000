import Foundation
import Observation

/// Information shown when the user taps a word.
struct WordInfo: Identifiable {
    let tapped: String
    let language: Language
    /// Dictionary headword, if found (may differ from the tapped form).
    let headword: String?
    let meaning: String?
    let example: String?
    let exampleTranslation: String?
    let level: Level?
    /// True when the match was a guess based on a shared stem.
    let approximate: Bool

    var id: String { "\(language.rawValue)-\(tapped)" }
}

/// Loads the bundled course files plus any downloaded monthly content packs
/// and merges them into one pool of content per language and level.
@MainActor
@Observable
final class ContentStore {
    private(set) var packs: [Language: CoursePack] = [:]
    /// Downloaded monthly packs, keyed by month id ("2026-12").
    private(set) var monthPacks: [Language: [String: CoursePack]] = [:]
    private(set) var isUpdating = false
    var updateMessage: String?
    /// Set when new lessons arrive in the background (shown as a banner).
    var newContentNotice: String?

    private var index: [Language: [String: (VocabItem, Level)]] = [:]
    private var glossaryIndex: [Language: [String: String]] = [:]

    init() { reload() }

    // MARK: Loading

    func reload() {
        for lang in Language.allCases {
            var pack = Self.loadBundled(lang) ?? CoursePack(version: nil, levels: [:])
            let downloaded = Self.loadDownloaded(lang)
            monthPacks[lang] = Dictionary(downloaded, uniquingKeysWith: { _, new in new })
            for (_, extra) in downloaded {
                for (key, content) in extra.levels {
                    var existing = pack.levels[key] ?? LevelContent()
                    existing.merge(content)
                    pack.levels[key] = existing
                }
            }
            packs[lang] = pack
            buildIndex(for: lang)
        }
    }

    func content(_ language: Language, _ level: Level) -> LevelContent {
        packs[language]?.levels[level.rawValue] ?? LevelContent()
    }

    /// The new material written for a given month, if it has been downloaded.
    func featured(_ language: Language, _ level: Level, month: MonthKey) -> LevelContent? {
        monthPacks[language]?[month.id]?.levels[level.rawValue]
    }

    func theme(_ language: Language, month: MonthKey) -> String? {
        monthPacks[language]?[month.id]?.theme
    }

    /// All vocabulary for a language (every level), used for fallback distractors.
    func allVocab(_ language: Language) -> [VocabItem] {
        Level.allCases.flatMap { content(language, $0).vocab }
    }

    private static func loadBundled(_ lang: Language) -> CoursePack? {
        guard let url = Bundle.main.url(forResource: lang.resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(CoursePack.self, from: data)
        } catch {
            print("⚠️ Failed to decode \(lang.resourceName).json: \(error)")
            return nil
        }
    }

    static var packsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ContentPacks", isDirectory: true)
    }

    /// Downloaded packs as (month id, pack), oldest first.
    private static func loadDownloaded(_ lang: Language) -> [(String, CoursePack)] {
        let dir = packsDirectory.appendingPathComponent(lang.rawValue, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap {
            guard let data = try? Data(contentsOf: $0),
                  let pack = try? JSONDecoder().decode(CoursePack.self, from: data) else { return nil }
            return ($0.deletingPathExtension().lastPathComponent, pack)
        }
    }

    // MARK: Monthly content packs

    /// Downloads one month's pack. Returns false if it isn't published (yet) or the network fails.
    private func download(_ lang: Language, month: MonthKey, template: String) async -> Bool {
        let urlString = template
            .replacingOccurrences(of: "{lang}", with: lang.rawValue)
            .replacingOccurrences(of: "{month}", with: month.id)
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            _ = try JSONDecoder().decode(CoursePack.self, from: data) // only save valid packs
            let dir = Self.packsDirectory.appendingPathComponent(lang.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("\(month.id).json"), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Runs quietly at launch and whenever the app comes back to the foreground
    /// (at most every few hours). Fetches any recent month that isn't on the phone yet,
    /// including next month's pack once it's published, so it's ready offline.
    func autoUpdate(force: Bool = false) async {
        let template = AppConfig.packURLTemplate
        guard AppConfig.autoUpdateEnabled, !template.isEmpty, !isUpdating else { return }
        let key = "lastAutoUpdate"
        let last = UserDefaults.standard.double(forKey: key)
        let now = Date().timeIntervalSince1970
        guard force || now - last > 4 * 3600 else { return }
        UserDefaults.standard.set(now, forKey: key)

        isUpdating = true
        defer { isUpdating = false }
        let current = MonthKey.current
        let months = [current, current.adding(months: 1), current.adding(months: -1), current.adding(months: -2)]
        var gotCurrent = false
        var gotAny = false
        for lang in Language.allCases {
            for month in months where monthPacks[lang]?[month.id] == nil {
                if await download(lang, month: month, template: template) {
                    gotAny = true
                    if month == current { gotCurrent = true }
                }
            }
        }
        if gotAny { reload() }
        if gotCurrent { newContentNotice = "New lessons for \(current.displayName) are ready!" }
    }

    /// The "Check for new content" button: re-downloads this and next month's packs.
    func checkForUpdates() async {
        let template = AppConfig.packURLTemplate
        guard !template.isEmpty else {
            updateMessage = "Add a content-pack address first."
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        let current = MonthKey.current
        var found: [String] = []
        for lang in Language.allCases {
            for month in [current, current.adding(months: 1)] {
                if await download(lang, month: month, template: template) {
                    found.append("\(lang.displayName) \(month.displayName)")
                }
            }
        }
        reload()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastAutoUpdate")
        updateMessage = found.isEmpty
            ? "No new pack is published for \(current.displayName) yet. Lessons still reshuffle every month."
            : "Up to date: \(found.joined(separator: ", "))."
    }

    func removeDownloadedPacks() {
        try? FileManager.default.removeItem(at: Self.packsDirectory)
        reload()
        updateMessage = "Removed downloaded packs."
    }

    var downloadedPackCount: Int {
        Language.allCases.reduce(0) { total, lang in
            let dir = Self.packsDirectory.appendingPathComponent(lang.rawValue)
            return total + ((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.count ?? 0)
        }
    }

    // MARK: Dictionary lookup

    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        s = s.replacingOccurrences(of: "\u{301}", with: "") // stress marks
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
            .replacingOccurrences(of: "ё", with: "е")
        let edges = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
            .subtracting(CharacterSet(charactersIn: "'"))
        s = s.trimmingCharacters(in: edges)
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    }

    private func buildIndex(for lang: Language) {
        var dict: [String: (VocabItem, Level)] = [:]
        var gloss: [String: String] = [:]
        for level in Level.allCases {
            let c = content(lang, level)
            for item in c.vocab {
                let keys = [item.word] + (item.forms ?? [])
                for k in keys {
                    let n = Self.normalize(k)
                    if dict[n] == nil { dict[n] = (item, level) }
                }
            }
            for reading in c.readings {
                for (k, v) in reading.glossary ?? [:] { gloss[Self.normalize(k)] = v }
            }
        }
        index[lang] = dict
        glossaryIndex[lang] = gloss
    }

    func lookup(_ raw: String, language: Language, glossary: [String: String]? = nil) -> WordInfo {
        let key = Self.normalize(raw)
        let display = raw.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces).subtracting(CharacterSet(charactersIn: "'’")))

        // The story's own glossary wins: it knows the meaning in context.
        if let local = glossary?.first(where: { Self.normalize($0.key) == key })?.value {
            let vocab = index[language]?[key]
            return WordInfo(tapped: display, language: language, headword: vocab?.0.word, meaning: local,
                            example: vocab?.0.example, exampleTranslation: vocab?.0.exampleTranslation,
                            level: vocab?.1, approximate: false)
        }
        if let (item, level) = index[language]?[key] {
            return WordInfo(tapped: display, language: language, headword: item.word, meaning: item.meaning,
                            example: item.example, exampleTranslation: item.exampleTranslation, level: level, approximate: false)
        }
        if let local = glossaryIndex[language]?[key] {
            return WordInfo(tapped: display, language: language, headword: nil, meaning: local,
                            example: nil, exampleTranslation: nil, level: nil, approximate: false)
        }
        // Stem guess: Russian/Ukrainian words inflect, so try matching a shared stem.
        if key.count >= 5, let dict = index[language] {
            let stem = String(key.prefix(max(4, key.count - 3)))
            if let match = dict.filter({ $0.key.count >= 4 && $0.key.hasPrefix(stem) })
                .min(by: { abs($0.key.count - key.count) < abs($1.key.count - key.count) }) {
                let (item, level) = match.value
                return WordInfo(tapped: display, language: language, headword: item.word, meaning: item.meaning,
                                example: item.example, exampleTranslation: item.exampleTranslation, level: level, approximate: true)
            }
        }
        return WordInfo(tapped: display, language: language, headword: nil, meaning: nil,
                        example: nil, exampleTranslation: nil, level: nil, approximate: false)
    }
}
