import SwiftUI

struct SettingsView: View {
    @Environment(ContentStore.self) private var content
    @Environment(ProgressStore.self) private var progress
    @AppStorage("speechRate") private var speechRate = 0.45
    @AppStorage("showTranslit") private var showTranslit = true
    @AppStorage("contentPackURL") private var packURL = ""
    @AppStorage("autoUpdate") private var autoUpdate = true
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Speaking speed")
                        HStack {
                            Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                            Slider(value: $speechRate, in: 0.25...0.6)
                            Image(systemName: "hare.fill").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Language.allCases) { lang in
                        HStack {
                            Text("\(lang.flag) \(lang.displayName) voice")
                            Spacer()
                            if SpeechService.hasVoice(for: lang) {
                                Button("Test") {
                                    SpeechService.shared.speak(lang == .russian ? "Привет! Как дела?" : "Привіт! Як справи?", language: lang)
                                }
                            } else {
                                Text("Not installed").foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text("Audio")
                } footer: {
                    Text("For the most natural pronunciation, download an \"Enhanced\" or \"Premium\" voice: iPhone Settings → Accessibility → Read & Speak → Voices → Russian / Ukrainian.")
                }

                Section("Display") {
                    Toggle("Show Latin transliteration", isOn: $showTranslit)
                }

                Section {
                    LabeledContent("Current set", value: MonthKey.current.displayName)
                    LabeledContent("Next refresh", value: "in \(MonthKey.daysUntilNext) days")
                    LabeledContent("Downloaded packs", value: "\(content.downloadedPackCount)")
                    Toggle("Download new lessons automatically", isOn: $autoUpdate)
                    TextField(AppConfig.defaultPackURL.isEmpty ? "https://…/{lang}/{month}.json" : AppConfig.defaultPackURL,
                              text: $packURL)
                        .font(.footnote)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        Task { await content.checkForUpdates() }
                    } label: {
                        HStack {
                            Text("Check for new content")
                            if content.isUpdating { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(content.isUpdating)
                    if let msg = content.updateMessage {
                        Text(msg).font(.footnote).foregroundStyle(.secondary)
                    }
                    if content.downloadedPackCount > 0 {
                        Button("Remove downloaded packs", role: .destructive) { content.removeDownloadedPacks() }
                    }
                } header: {
                    Text("Monthly content")
                } footer: {
                    Text("New words and stories are written every month and download by themselves when you open the app with internet. After that everything works offline. Leave the address empty to use the default source.")
                }

                Section("Progress") {
                    LabeledContent("Total XP", value: "\(progress.data.xp)")
                    LabeledContent("Day streak", value: "\(progress.currentStreak)")
                    Button("Reset all progress", role: .destructive) { confirmReset = true }
                }

                Section {
                    LabeledContent("App", value: "LanguageLearner3000")
                    LabeledContent("Version", value: "1.0")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Reset all progress?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { progress.reset() }
            }
        }
    }
}
