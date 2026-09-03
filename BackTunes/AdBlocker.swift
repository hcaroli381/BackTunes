import Foundation
import WebKit

/// Two-layer ad blocking:
///  1. WKContentRuleList (Safari-style content blocker) strips ad/tracking
///     domains at the network layer inside every webview.
///  2. A user script clicks YouTube's "Skip" button the instant it appears.
enum AdBlocker {

    private static var prepared = false

    static func prepare() async {
        guard !prepared else { return }
        prepared = true

        guard let store = WKContentRuleListStore.default() else { return }

        do {
            // Reuse the rules compiled on a previous launch when possible.
            let list = try await lookUpOrCompile(store, id: identifier, json: ruleJSON)
            await MainActor.run { compiledRuleList = list }
        } catch {
            NSLog("BackTunes: failed to prepare content blocker rules: \(error)")
        }
    }

    private static let identifier = "bt-blocker"

    private static var compiledRuleList: WKContentRuleList?

    private static func lookUpOrCompile(_ store: WKContentRuleListStore,
                                        id: String,
                                        json: String) async throws -> WKContentRuleList {
        // The async overloads on WKContentRuleListStore are unavailable to
        // Swift; wrap the completion-handler API instead.
        let existing: WKContentRuleList? = await withCheckedContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: id) { list, _ in
                continuation.resume(returning: list)
            }
        }
        if let existing = existing { return existing }

        return try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { list, error in
                if let list = list {
                    continuation.resume(returning: list)
                } else if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: URLError(.badURL))
                }
            }
        }
    }

    /// Attach to a webview configuration before any page loads.
    static func apply(to configuration: WKWebViewConfiguration, autoSkip: Bool = true) {
        if let list = compiledRuleList {
            configuration.userContentController.add(list, forMainResourceOnly: false)
        }
        if autoSkip {
            configuration.userContentController.addUserScript(WKUserScript(
                source: skipScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true))
        }
    }

    // MARK: - Rules

    private static let blockedDomains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "google-analytics.com", "googletagmanager.com", "googletagservices.com",
        "adservice.google.com", "pagead2.googlesyndication.com",
        "static.doubleclick.net", "ade.googlesyndication.com",
        "2mdn.net", "ad.youtube.com", "ads.youtube.com",
        "scorecardresearch.com", "quantserve.com", "bluekai.com",
        "demdex.net", "agkn.com", "admob.com",
        "advertising.com", "atdmt.com", "amazon-adsystem.com",
    ]

    /// Plain JSON string — this is exactly what Safari content blockers ship.
    private static var ruleJSON: String {
        var triggers: [[String: Any]] = blockedDomains.map { domain in
            [
                "trigger": ["url-filter": ".*\(NSRegularExpression.escapedPattern(for: domain)).*"],
                "action": ["type": "block"],
            ]
        }
        // Hide known YouTube ad slots in the page layout.
        triggers.append([
            "trigger": ["url-filter": ".*"],
            "action": [
                "type": "css-display-none",
                "selector": ".ytd-display-ad-renderer, .ytd-promoted-sparkles-web-renderer, ytd-in-feed-ad-layout-renderer, #masthead-ad, ytd-merch-shelf-renderer",
            ],
        ])
        guard let data = try? JSONSerialization.data(withJSONObject: triggers),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Skip script

    private static let skipScript = """
    (function () {
      if (window.__btAdSkipInstalled) return;
      window.__btAdSkipInstalled = true;

      function clickSkip() {
        var btn = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
        if (btn) { btn.click(); return; }
        var v = document.querySelector('video');
        if (v && v.duration && v.duration < 31) {
          // Short unskippable ad: jump past it.
          if (document.querySelector('.ytp-ad-player-overlay, .ytp-ad-text')) {
            v.currentTime = v.duration;
          }
        }
      }

      setInterval(clickSkip, 500);
      document.addEventListener('DOMContentLoaded', clickSkip);
    })();
    """
}
