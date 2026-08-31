import SwiftUI

/// Placeholder for the Organize Now pass; replaced wholesale in Task 16. The
/// shelf's toolbar references it now so the button has somewhere to go.
struct OrganizeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Organize Now")
                .font(.headline)
            Text("Not implemented yet.")
                .foregroundStyle(.secondary)
            Button("Close") { dismiss() }
        }
        .padding(24)
        .frame(width: 360)
    }
}
