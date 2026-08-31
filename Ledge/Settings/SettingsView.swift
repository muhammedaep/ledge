import SwiftUI

/// Placeholder settings scene. It exists so the shelf's `SettingsLink` has a
/// scene to open; its tabs are filled in by later tasks.
struct SettingsView: View {
    var body: some View {
        TabView {
            Text("General")
                .tabItem { Label("General", systemImage: "gearshape") }
            Text("Rules")
                .tabItem { Label("Rules", systemImage: "list.bullet") }
        }
        .frame(width: 520, height: 380)
    }
}
