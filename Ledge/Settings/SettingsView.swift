import SwiftUI

/// The settings scene the shelf's `SettingsLink` opens.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            RulesPane()
                .tabItem { Label("Rules", systemImage: "list.bullet") }
        }
        // One frame for both tabs, sized for the taller one. A rules row is a
        // name, an extensions field, a subdivision picker and whatever warning
        // applies to it; at 380 points barely two of them fit, and the pane
        // whose whole subject is the order of a list is the one that must show
        // enough of the list to reorder it.
        .frame(width: 560, height: 460)
    }
}
