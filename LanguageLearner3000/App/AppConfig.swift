import Foundation

enum AppConfig {
    /// Where the monthly content packs are published (by the GitHub Action in
    /// `.github/workflows/monthly-content.yml`). `{lang}` becomes ru/uk and
    /// `{month}` becomes e.g. 2026-12. Can be overridden in Settings.
    static let defaultPackURL =
        "https://raw.githubusercontent.com/OmegaCluster556/LanguageLearner3000/main/packs/{lang}/{month}.json"

    /// The pack address in use: the one typed in Settings, or the default above.
    static var packURLTemplate: String {
        let custom = UserDefaults.standard.string(forKey: "contentPackURL")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? defaultPackURL : custom
    }

    static var autoUpdateEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true
    }
}
