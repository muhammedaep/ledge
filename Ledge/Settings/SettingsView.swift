import SwiftUI

/// The settings scene the shelf's `SettingsLink` opens.
struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            // Here rather than inside `GeneralPane`, where the failures that
            // prompted this come from. `updateProjects` reports through
            // `lastError`, and the only screens rendering that were the shelf
            // and the Organize sheet — so removing or renaming a project in
            // Settings and having the write refused was silent here, then
            // surfaced later in the menu bar popover, worded as if it had come
            // from something the user was doing there.
            //
            // At this level it also covers the Rules pane and anything added
            // later. `RulesPane` keeps its own inline "Couldn't save. Nothing
            // was changed." beside the Save button and the two do not conflict:
            // that one says the click failed, this one carries the specific
            // reason `updateRules` put in `lastError` — which is the very
            // detail that pane's comment complains was being sent somewhere the
            // user is not looking.
            ErrorBanner(message: state.lastError, horizontalPadding: 14, topPadding: 10,
                    onOpenPrivacySettings: state.lastErrorOffersPrivacySettings
                        ? { PrivacySettings.open() } : nil) {
                state.clearError()
            }

            TabView {
                GeneralPane()
                    .tabItem { Label("General", systemImage: "gearshape") }
                RulesPane()
                    .tabItem { Label("Rules", systemImage: "list.bullet") }
            }
        }
        // One frame for both tabs, sized for the taller one. A rules row is a
        // name, an extensions field, a subdivision picker and whatever warning
        // applies to it; at 380 points barely two of them fit, and the pane
        // whose whole subject is the order of a list is the one that must show
        // enough of the list to reorder it.
        .frame(width: 560, height: 460)
        // The same guard the Organize sheet takes, for the same reason: a
        // watcher failure from an hour ago would otherwise be sitting here when
        // the window opens, reading as a verdict on whatever the user clicks
        // next. Everything this banner was added for fails *while* Settings is
        // open, so it arrives after this.
        .onAppear { state.clearError() }
    }
}
