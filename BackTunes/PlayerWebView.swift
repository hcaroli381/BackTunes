import SwiftUI
import WebKit

/// SwiftUI wrapper around the webview that hosts YouTube's embed player.
/// The embed is the key to background playback: it is treated as the app's
/// own audio, which iOS keeps alive when the screen locks.
struct PlayerWebView: UIViewRepresentable {
    let video: Video

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsContentJavaScript = true

        // Content-blocker rules + ad auto-skip script (per user settings).
        let settings = SettingsStore.shared
        if settings.adBlockEnabled {
            AdBlocker.apply(to: config, autoSkip: settings.autoSkip)
        }

        // State bridge: player events -> PlayerModel.
        config.userContentController.addUserScript(WKUserScript(
            source: Self.bridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true))
        config.userContentController.add(context.coordinator, name: "btBridge", forMainFrameOnly: true)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false

        PlayerModel.shared.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedVideoID != video.id {
            context.coordinator.loadedVideoID = video.id
            webView.load(video.embedURL)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var loadedVideoID: String?

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "btBridge", let body = message.body as? [String: Any] else { return }
            PlayerModel.shared.handleWebEvent(body)
        }
    }

    // MARK: - Injected script

    /// Reports playback state to the app. The embed player creates its
    /// <video> element some time after page load, so we poll for it.
    private static let bridgeScript = """
    (function () {
      if (window.__btBridgeInstalled) return;
      window.__btBridgeInstalled = true;

      function post(obj) {
        try { window.webkit.messageHandlers.btBridge.postMessage(obj); } catch (e) {}
      }

      var video = null;
      function report() {
        if (!video) return;
        post({
          event: 'state',
          playing: !video.paused && !video.ended && video.readyState > 2,
          currentTime: video.currentTime,
          duration: video.duration || 0
        });
      }

      function attach(v) {
        video = v;
        ['timeupdate', 'play', 'pause', 'ended', 'durationchange'].forEach(function (evt) {
          v.addEventListener(evt, report);
        });
        report();
        setInterval(report, 1000);
        setTimeout(function () { post({ event: 'meta', title: document.title }); }, 2000);
      }

      (function poll() {
        var v = document.querySelector('video');
        if (v) { attach(v); return; }
        setTimeout(poll, 200);
      })();

      // Ads toggle a class on the player container; surface it to the app.
      function installAdObserver() {
        new MutationObserver(function () {
          var ad = document.querySelector('.ytp-ad-player-overlay, .ytp-ad-text, .ytp-ad-badge');
          post({ event: 'ad', active: !!ad });
        }).observe(document.body, { childList: true, subtree: true });
      }
      if (document.body) { installAdObserver(); }
      else { document.addEventListener('DOMContentLoaded', installAdObserver); }

      // Called by PlayerModel's keep-alive timer while the screen is off.
      window.__btWake = function () {
        post({ event: 'wake' });
        var v = document.querySelector('video');
        if (v && v.paused === false) {
          // Nudge the media element so iOS does not tear it down.
          v.dispatchEvent(new Event('timeupdate'));
        }
      };
    })();
    """
}
