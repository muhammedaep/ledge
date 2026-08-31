import SwiftUI

/// The settings scene the shelf's `SettingsLink` opens. Rules fill in later.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            Text("Rules")
                .tabItem { Label("Rules", systemImage: "list.bullet") }
        }
        .frame(width: 520, height: 380)
    }
}
