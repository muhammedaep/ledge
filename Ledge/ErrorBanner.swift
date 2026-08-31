import SwiftUI

/// The one banner that renders `AppState.lastError`.
///
/// Two screens need it and only one of them is ever visible: the Organize sheet
/// sits on top of the shelf, so the shelf's own banner is covered exactly when a
/// batch is failing. That made a second copy necessary — and left two copies of
/// the icon, the wording, the dismiss button and its tooltip to drift apart,
/// which is a bad trade for a control whose whole job is telling the user the
/// truth about their files.
///
/// The padding differs because the two containers do: the shelf lays out on a
/// 12-point gutter, the sheet on 14.
struct ErrorBanner: View {
    let message: String?
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let onDismiss: () -> Void

    var body: some View {
        if let message {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Dismiss"))
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
        }
    }
}
