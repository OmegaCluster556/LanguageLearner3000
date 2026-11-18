import SwiftUI

@main
struct LanguageLearner3000App: App {
    @State private var content = ContentStore()
    @State private var progress = ProgressStore()

    init() { SpeechService.warmUp() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(content)
                .environment(progress)
        }
    }
}

struct RootView: View {
    @State private var speech = SpeechService.shared
    @Environment(ContentStore.self) private var content
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            LanguageHomeView(language: .russian)
                .tabItem { Label("Russian", systemImage: "r.square.fill") }
            LanguageHomeView(language: .ukrainian)
                .tabItem { Label("Ukrainian", systemImage: "u.square.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        // Fetch new monthly lessons automatically (quietly, at most every few hours).
        .task { await content.autoUpdate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await content.autoUpdate() } }
        }
        .overlay(alignment: .top) {
            if let notice = content.newContentNotice {
                Label(notice, systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 6)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { content.newContentNotice = nil }
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { content.newContentNotice = nil }
                    }
            }
        }
        .animation(.spring, value: content.newContentNotice)
        .alert("\(speech.missingVoice?.displayName ?? "") voice not installed",
               isPresented: Binding(get: { speech.missingVoice != nil }, set: { if !$0 { speech.missingVoice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To hear pronunciation, open the iPhone Settings app → Accessibility → Read & Speak (Spoken Content) → Voices, and download a \(speech.missingVoice?.displayName ?? "") voice.")
        }
    }
}
