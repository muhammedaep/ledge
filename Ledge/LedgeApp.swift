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
        MenuBarExtra("Ledge", systemImage: "tray.and.arrow.down") {
            ShelfView()
                .environment(state)
        }
        .menuBarExtraStyle(.window)
    }
}
