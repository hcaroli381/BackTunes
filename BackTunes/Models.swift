import Foundation

struct Video: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let channel: String
    let viewCountText: String?
    let durationText: String?
    let thumbnailURL: URL?

    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }

    /// The embedded player is what makes background playback possible:
    /// it is a plain HTML5 player that iOS treats as normal app audio.
    var embedURL: URL {
        URL(string: "https://www.youtube.com/embed/\(id)?autoplay=1&playsinline=1&rel=0&modestbranding=1&iv_load_policy=3")!
    }
}

/// Persists bookmarks and play history to UserDefaults as JSON.
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    enum List { case bookmarks, history }

    @Published private(set) var bookmarks: [Video] = [] {
        didSet { persist(key: "bt.bookmarks", videos: bookmarks) }
    }

    @Published private(set) var history: [Video] = [] {
        didSet { persist(key: "bt.history", videos: history) }
    }

    private init() {
        bookmarks = Self.load(key: "bt.bookmarks")
        history = Self.load(key: "bt.history")
    }

    func isBookmarked(_ video: Video) -> Bool {
        bookmarks.contains { $0.id == video.id }
    }

    func toggleBookmark(_ video: Video) {
        if isBookmarked(video) {
            bookmarks.removeAll { $0.id == video.id }
        } else {
            bookmarks.insert(video, at: 0)
        }
    }

    func addToHistory(_ video: Video) {
        history.removeAll { $0.id == video.id }
        history.insert(video, at: 0)
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
    }

    func remove(at offsets: IndexSet, from list: List) {
        switch list {
        case .bookmarks: bookmarks.remove(atOffsets: offsets)
        case .history: history.remove(atOffsets: offsets)
        }
    }

    func clearHistory() {
        history.removeAll()
    }

    private func persist(key: String, videos: [Video]) {
        if let data = try? JSONEncoder().encode(videos) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load(key: String) -> [Video] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Video].self, from: data)) ?? []
    }
}
