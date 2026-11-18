import Foundation

/// Converts Cyrillic to Latin letters so you can read words without typing Cyrillic.
enum Transliterator {
    private static let russian: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "zh", "з": "z",
        "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r",
        "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
        "ъ": "", "ы": "y", "ь": "'", "э": "e", "ю": "yu", "я": "ya",
    ]

    private static let ukrainian: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "h", "ґ": "g", "д": "d", "е": "e", "є": "ye", "ж": "zh",
        "з": "z", "и": "y", "і": "i", "ї": "yi", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n",
        "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts",
        "ч": "ch", "ш": "sh", "щ": "shch", "ь": "'", "ю": "yu", "я": "ya", "'": "", "’": "",
    ]

    static func latin(_ text: String, language: Language) -> String {
        let table = language == .russian ? russian : ukrainian
        var out = ""
        for ch in text {
            let lower = Character(ch.lowercased())
            if let mapped = table[lower] {
                if ch.isUppercase, let first = mapped.first {
                    out += first.uppercased() + mapped.dropFirst()
                } else {
                    out += mapped
                }
            } else {
                out.append(ch)
            }
        }
        return out
    }
}
