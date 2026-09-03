import AVFoundation

enum AudioSessionManager {
    /// Sets the audio session category that lets playback continue while the
    /// screen is locked and the app is in the background. Requires the
    /// `audio` entry in UIBackgroundModes (Info.plist).
    static func prepareForBackgroundAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            NSLog("BackTunes: failed to set audio session category: \(error)")
        }
    }
}
