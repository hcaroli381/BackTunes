import SwiftUI

@main
struct BackTunesApp: App {
    @ObservedObject private var player = PlayerModel.shared
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var settings = SettingsStore.shared

    init() {
        // Allow audio to keep playing when the screen locks / app backgrounds.
        AudioSessionManager.prepareForBackgroundAudio()
        // Compile the content-blocker rules once, before the first video plays.
        Task { await AdBlocker.prepare() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .environmentObject(library)
                .environmentObject(settings)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var player: PlayerModel
    @State private var expanded = false

    var body: some View {
        GeometryReader { geo in
            TabView {
                SearchScreen()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                LibraryScreen()
                    .tabItem { Label("Library", systemImage: "books.vertical") }
                SettingsScreen()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let video = player.currentVideo {
                    PlayerOverlayView(video: video, expanded: $expanded, screenHeight: geo.size.height)
                        .transition(.move(edge: .bottom))
                }
            }
            .onChange(of: player.currentVideo) { video in
                if video != nil { expanded = true }
            }
        }
    }
}
