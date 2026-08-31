import SwiftUI

@main
struct LedgeApp: App {
    // Declared without a default: a default expression here would be evaluated
    // *and then* overwritten by `init`, building two AppStates and opening two
    // journals, one of which is silently discarded.
    @State private var state: AppState

    init() {
        let state = AppState()
        _state = State(initialValue: state)
        state.startWatching()
    }

    var body: some Scene {
        // The icon changes shape while a project is active, so the user can see
        // that downloads are being diverted without opening the shelf.
        MenuBarExtra {
            ShelfView()
                .environment(state)
        } label: {
            Image(systemName: state.activeProject == nil
                  ? "tray.and.arrow.down"
                  : "folder.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
