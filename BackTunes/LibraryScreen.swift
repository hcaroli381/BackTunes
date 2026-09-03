import SwiftUI

struct LibraryScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var segment = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $segment) {
                    Text("Bookmarks").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if segment == 0 {
                    videoList(library.bookmarks, list: .bookmarks, emptyText: "Bookmark videos from search results to find them here.")
                } else {
                    videoList(library.history, list: .history, emptyText: "Videos you play will show up here.")
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if segment == 1 && !library.history.isEmpty {
                    Button("Clear") { library.clearHistory() }
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func videoList(_ videos: [Video], list: LibraryStore.List, emptyText: String) -> some View {
        if videos.isEmpty {
            Spacer()
            Text(emptyText).foregroundStyle(.secondary)
            Spacer()
        } else {
            List {
                ForEach(videos) { video in
                    VideoRow(video: video)
                }
                .onDelete { library.remove(at: $0, from: list) }
            }
            .listStyle(.plain)
        }
    }
}

struct SettingsScreen: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback") {
                    Toggle("Play in background / screen off", isOn: .constant(true))
                        .disabled(true)
                }
                Section("Ad blocking") {
                    Toggle("Block ads in player", isOn: $settings.adBlockEnabled)
                    Toggle("Auto-skip ads", isOn: $settings.autoSkip)
                }
                Section("About") {
                    LabeledContent("App", value: "BackTunes 1.0")
                    LabeledContent("Player", value: "YouTube embed")
                    LabeledContent("Install", value: "SideStore / AltStore")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
