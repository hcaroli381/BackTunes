import SwiftUI

struct SearchScreen: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""
    @State private var results: [Video] = []
    @State private var continuation: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                content
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search YouTube", text: $query)
                .submitLabel(.search)
                .onSubmit { Task { await runSearch() } }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && results.isEmpty {
            Spacer()
            ProgressView("Searching…")
            Spacer()
        } else if let errorMessage = errorMessage {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text(errorMessage).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding()
            Spacer()
        } else if results.isEmpty {
            Spacer()
            Text("Search for something to play.")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(results) { video in
                VideoRow(video: video)
            }
            if continuation != nil {
                Button {
                    Task { await loadMore() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Load more")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await YouTubeService.search(q)
            results = page.videos
            continuation = page.continuationToken
            if results.isEmpty {
                errorMessage = "No results found."
            }
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }

    private func loadMore() async {
        guard let token = continuation, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await YouTubeService.searchMore(query, token: token)
            results.append(contentsOf: page.videos)
            continuation = page.continuationToken
        } catch {
            errorMessage = "Couldn't load more: \(error.localizedDescription)"
        }
    }
}

/// A search result / library row: thumbnail, title, channel.
struct VideoRow: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore
    let video: Video

    var body: some View {
        Button {
            player.play(video)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ThumbnailView(url: video.thumbnailURL)
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(player.currentVideo?.id == video.id ? Color.accentColor : .primary)
                    Text(video.channel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let meta = [video.viewCountText, video.durationText].compactMap({ $0 }).joined(separator: " · ") as String?, !meta.isEmpty {
                        Text(meta)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    library.toggleBookmark(video)
                } label: {
                    Image(systemName: library.isBookmarked(video) ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

/// Async thumbnail with a placeholder.
struct ThumbnailView: View {
    let url: URL?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let url = url {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "play.rectangle").foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "play.rectangle").foregroundStyle(.secondary)
            }
        }
    }
}
