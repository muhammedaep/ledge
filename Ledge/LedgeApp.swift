import SwiftUI

@main
struct LedgeApp: App {
    var body: some Scene {
        MenuBarExtra("Ledge", systemImage: "tray.and.arrow.down") {
            ShelfView()
        }
        .menuBarExtraStyle(.window)
    }
}
