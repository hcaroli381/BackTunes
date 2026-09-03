import Foundation

/// Search over YouTube's public web client (Innertube API) — the same JSON
/// endpoint the youtube.com web app uses. No API key required.
enum YouTubeService {

    struct SearchResult {
        let videos: [Video]
        let continuationToken: String?
    }

    static func search(_ query: String) async throws -> SearchResult {
        try await searchPage(query, token: nil)
    }

    static func searchMore(_ query: String, token: String) async throws -> SearchResult {
        try await searchPage(query, token: token)
    }

    private static func searchPage(_ query: String, token: String?) async throws -> SearchResult {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/search?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Origin")

        let context: [String: Any] = [
            "client": [
                "clientName": "WEB",
                "clientVersion": "2.20240702.01.00",
                "hl": "en",
                "gl": "US",
            ]
        ]
        var params: [String: Any] = ["query": query, "context": context]
        if let token = token {
            params["continuation"] = token
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try parseSearchResponse(data)
    }

    // MARK: - Parsing

    private static func parseSearchResponse(_ data: Data) throws -> SearchResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        var rawItems: [[String: Any]] = []
        var continuation: String?

        if let contents = key(json, "contents", "twoColumnSearchResultsRenderer", "primaryContents", "sectionListRenderer", "contents") as? [[String: Any]] {
            // First page.
            for sectionItem in contents {
                if let itemSection = key(sectionItem, "itemSectionRenderer", "contents") as? [[String: Any]] {
                    rawItems.append(contentsOf: itemSection)
                }
                if let token = key(sectionItem, "continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token") as? String {
                    continuation = token
                }
            }
        } else if let actions = key(json, "onResponseReceivedActions") as? [[String: Any]] {
            // Continuation page.
            for action in actions {
                if let items = key(action, "appendContinuationItemsAction", "continuationItems") as? [[String: Any]] {
                    rawItems.append(contentsOf: items)
                }
                if let token = key(action, "appendContinuationItemsAction", "continuationItems", "continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token") as? String {
                    continuation = token
                }
            }
            rawItems.removeAll { $0["continuationItemRenderer"] != nil }
        }

        var videos: [Video] = []
        for item in rawItems {
            guard let r = item["videoRenderer"] as? [String: Any],
                  let id = r["videoId"] as? String else { continue }

            let title = (key(r, "title", "runs") as? [[String: Any]])?
                .compactMap { $0["text"] as? String }.joined() ?? "(untitled)"

            let channel = (key(r, "ownerText", "runs") as? [[String: Any]])?
                .first.flatMap { $0["text"] as? String } ?? ""

            let views = (key(r, "viewCountText", "simpleText") as? String)
                ?? (key(r, "shortViewCountText", "simpleText") as? String)

            let length = (key(r, "lengthText", "simpleText") as? String)
                ?? (key(r, "thumbnailOverlayTimeStatusRenderer", "text", "simpleText") as? String)

            let thumbPath = (key(r, "thumbnail", "thumbnails") as? [[String: Any]])?
                .compactMap { $0["url"] as? String }.last
            let thumbURL = thumbPath.flatMap { URL(string: "https:\($0)") }

            videos.append(Video(
                id: id,
                title: title,
                channel: channel,
                viewCountText: views,
                durationText: length,
                thumbnailURL: thumbURL))
        }

        return SearchResult(videos: videos, continuationToken: continuation)
    }

    /// Digs through nested JSON dictionaries: key(json, "a", "b", "c").
    /// When the path crosses an array, the last element is used
    /// (continuation tokens live on the last item of continuationItems).
    private static func key(_ value: Any?, _ path: String...) -> Any? {
        var current = value
        for name in path {
            if let array = current as? [Any] {
                current = array.last
            }
            current = (current as? [String: Any])?[name]
        }
        return current
    }
}
