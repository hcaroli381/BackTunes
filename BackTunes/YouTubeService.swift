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

        var context: [String: Any] = [
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
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        var rawItems: [[String: Any]] = []
        var continuation: String?

        if let contents = json["contents"] as? [String: Any] {
            // First page.
            if let twoCol = contents["twoColumnSearchResultsRenderer"]?["primaryContents"] as? [String: Any],
               let section = twoCol["sectionListRenderer"]?["contents"] as? [[String: Any]] {
                for sectionItem in section {
                    if let itemSection = sectionItem["itemSectionRenderer"]?["contents"] as? [[String: Any]] {
                        rawItems.append(contentsOf: itemSection)
                    }
                    if let contItem = sectionItem["continuationItemRenderer"]?["continuationEndpoint"]?["continuationCommand"]?["token"] as? String {
                        continuation = contItem
                    }
                }
            }
        } else if let onResp = json["onResponseReceivedActions"] as? [[String: Any]] {
            // Continuation page.
            for action in onResp {
                if let append = action["appendContinuationItemsAction"]?["continuationItems"] as? [[String: Any]] {
                    rawItems.append(contentsOf: append)
                }
                if let contItem = action["appendContinuationItemsAction"]?["continuationItems"]?.last?["continuationItemRenderer"]?["continuationEndpoint"]?["continuationCommand"]?["token"] as? String {
                    continuation = contItem
                }
            }
            rawItems.removeAll { $0["continuationItemRenderer"] != nil }
        }

        var videos: [Video] = []
        for item in rawItems {
            guard let r = item["videoRenderer"] as? [String: Any],
                  let id = r["videoId"] as? String else { continue }

            let title = ((r["title"] as? [String: Any])?["runs"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }.joined() ?? "(untitled)"

            let channel = ((r["ownerText"] as? [String: Any])?["runs"] as? [[String: Any]])?
                .first?["text"] as? String ?? ""

            let views = ((r["viewCountText"] as? [String: Any])?["simpleText"] as? String)
                ?? ((r["shortViewCountText"] as? [String: Any])?["simpleText"] as? String)

            let length = ((r["lengthText"] as? [String: Any])?["simpleText"] as? String)
                ?? ((r["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["text"]?["simpleText"] as? String)

            let thumbURL = ((r["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?
                .compactMap { $0["url"] as? String }.last
                .flatMap { URL(string: "https:\($0)") }

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
}
