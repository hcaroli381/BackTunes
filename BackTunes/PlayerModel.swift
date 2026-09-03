import AVFoundation
import Foundation
import MediaPlayer
import UIKit
import WebKit

/// Owns the playback state, the lock-screen (Now Playing) info and the
/// keep-alive machinery that keeps the web player running with the screen off.
final class PlayerModel: NSObject, ObservableObject {
    static let shared = PlayerModel()

    @Published var currentVideo: Video?
    @Published var isPlaying = false
    @Published var isAd = false
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var title = ""
    @Published var channel = ""

    weak var webView: WKWebView?

    private var silencePlayer: AVAudioPlayer?
    private var wakeTimer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isScrubbing = false
    private var lastReportedElapsed: Double = 0
    private var lastReportDate = Date()

    private override init() {
        super.init()
        setupRemoteCommands()
        prepareSilencePlayer()
        NotificationCenter.default.addObserver(
            self, selector: #selector(enteredBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(enteredForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    // MARK: - Public control

    func play(_ video: Video) {
        // Re-tapping the current video just restarts it.
        if currentVideo?.id == video.id {
            runJS("var v=document.querySelector('video'); if(v){ v.currentTime=0; v.play().catch(function(){}); }")
            elapsed = 0
            lastReportedElapsed = 0
            lastReportDate = Date()
            activateAudioSession()
            return
        }

        title = video.title
        channel = video.channel
        elapsed = 0
        duration = 0
        isAd = false
        isPlaying = false
        lastReportedElapsed = 0
        lastReportDate = Date()

        currentVideo = video
        UIApplication.shared.beginReceivingRemoteControlEvents()
        activateAudioSession()
        fetchArtwork(for: video)
        updateNowPlayingInfo()
        LibraryStore.shared.addToHistory(video)
    }

    func stop() {
        currentVideo = nil
        webView = nil
        isPlaying = false
        isAd = false
        elapsed = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        runJS("document.querySelector('video') && document.querySelector('video').play().catch(function(){});")
        activateAudioSession()
    }

    func pause() {
        runJS("document.querySelector('video') && document.querySelector('video').pause();")
    }

    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        runJS("var v=document.querySelector('video'); if(v){ v.currentTime=\(clamped); }")
        elapsed = clamped
        lastReportedElapsed = clamped
        lastReportDate = Date()
        updateNowPlayingInfo()
    }

    func skipForward() { seek(to: elapsed + 15) }
    func skipBackward() { seek(to: elapsed - 15) }

    func beginScrubbing() { isScrubbing = true }

    func endScrubbing() {
        isScrubbing = false
        seek(to: elapsed)
    }

    // MARK: - Events from the web player

    func handleWebEvent(_ body: [String: Any]) {
        switch body["event"] as? String {
        case "state":
            let playing = body["playing"] as? Bool ?? false
            let time = body["currentTime"] as? Double
            let newDuration = body["duration"] as? Double
            if !isScrubbing, let time = time {
                elapsed = time
                lastReportedElapsed = time
                lastReportDate = Date()
            }
            if let newDuration = newDuration, newDuration > 0 { duration = newDuration }
            if playing && !isPlaying { activateAudioSession() }
            isPlaying = playing
            updateNowPlayingInfo()

        case "ad":
            isAd = body["active"] as? Bool ?? false

        case "meta":
            // Title picked up from the player, e.g. after clicking a related video.
            if let raw = body["title"] as? String, !raw.isEmpty {
                let cleaned = raw.hasSuffix(" - YouTube") ? String(raw.dropLast(10)) : raw
                if !cleaned.isEmpty && cleaned != title {
                    title = cleaned
                    updateNowPlayingInfo()
                }
            }

        default:
            break
        }
    }

    /// Extrapolates the position between web events: while the screen is off
    /// the webview's JS timers are throttled, so we project from the wall clock.
    private var projectedElapsed: Double {
        guard isPlaying else { return lastReportedElapsed }
        return lastReportedElapsed + Date().timeIntervalSince(lastReportDate)
    }

    // MARK: - Keep-alive for background / screen-off playback

    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("BackTunes: audio session activation failed: \(error)")
        }
    }

    private func prepareSilencePlayer() {
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav") else { return }
        silencePlayer = try? AVAudioPlayer(contentsOf: url)
        silencePlayer?.numberOfLoops = -1
        silencePlayer?.volume = 0.01
    }

    @objc private func enteredBackground() {
        guard currentVideo != nil else { return }
        // Ask iOS for extra runtime so the keep-alive survives brief suspensions.
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "BackTunes keep-alive") { [weak self] in
            self?.endBackgroundTask()
        }
        // A silent, looping native audio track keeps the process alive so the
        // web player's own audio is never suspended.
        silencePlayer?.play()
        startWakeTimer()
    }

    @objc private func enteredForeground() {
        stopWakeTimer()
        silencePlayer?.pause()
        endBackgroundTask()
    }

    private func startWakeTimer() {
        stopWakeTimer()
        wakeTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.webView?.evaluateJavaScript("window.__btWake && window.__btWake();", completionHandler: nil)
        }
    }

    private func stopWakeTimer() {
        wakeTimer?.invalidate()
        wakeTimer = nil
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Lock screen / Now Playing

    private var artwork: MPMediaItemArtwork?

    /// Downloads the video thumbnail so it shows up on the lock screen.
    private func fetchArtwork(for video: Video) {
        artwork = nil
        guard let url = video.thumbnailURL else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async {
                guard self?.currentVideo?.id == video.id else { return }
                self?.artwork = art
                self?.updateNowPlayingInfo()
            }
        }.resume()
    }

    private func updateNowPlayingInfo() {
        guard currentVideo != nil else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title.isEmpty ? "YouTube" : title,
            MPMediaItemPropertyArtist: channel.isEmpty ? "BackTunes" : channel,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: projectedElapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork = artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayback(); return .success }
        center.skipBackwardCommand.addTarget { [weak self] _ in self?.skipBackward(); return .success }
        center.skipForwardCommand.addTarget { [weak self] _ in self?.skipForward(); return .success }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.preferredIntervals = [15]
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: e.positionTime)
            }
            return .success
        }
    }

    private func runJS(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
}
