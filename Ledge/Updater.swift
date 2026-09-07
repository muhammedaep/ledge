import Combine
import Sparkle
import SwiftUI

/// Sparkle, held once for the life of the app.
///
/// The controller starts the updater on creation, which is what schedules
/// the daily background check; `LedgeApp` touches `shared` at launch so that
/// happens whether or not Settings is ever opened. The feed URL and the
/// public key it verifies downloads against live in `Info.plist`
/// (`SUFeedURL`, `SUPublicEDKey`); the matching private key is in the
/// keychain of the Mac that cuts releases, and nowhere else.
///
/// Sparkle's own windows do the talking — "a new version is available",
/// progress, "install and relaunch" — so this class only exposes the two
/// things Settings needs: whether a check can start right now, and the
/// automatic-checks switch.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    let controller: SPUStandardUpdaterController

    /// False while a check or an install is already under way.
    @Published private(set) var canCheck = false

    private var observation: NSKeyValueObservation?

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates,
                                                  options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = value }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }
}
