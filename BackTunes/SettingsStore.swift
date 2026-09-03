import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var adBlockEnabled: Bool {
        didSet { defaults.set(adBlockEnabled, forKey: "bt.adBlockEnabled") }
    }

    @Published var autoSkip: Bool {
        didSet { defaults.set(autoSkip, forKey: "bt.autoSkip") }
    }

    private let defaults = UserDefaults.standard

    private init() {
        adBlockEnabled = defaults.object(forKey: "bt.adBlockEnabled") as? Bool ?? true
        autoSkip = defaults.object(forKey: "bt.autoSkip") as? Bool ?? true
    }
}
