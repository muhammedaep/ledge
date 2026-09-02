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
    /// Non-nil only when there is a route out of this failure — see
    /// `AppState.isPermissionDenied` for the one that offers Privacy Settings.
    ///
    /// Declared before `onDismiss` on purpose: the trailing closure at every
    /// call site binds to the last parameter, and this one is not a literal.
    var action: (title: String, run: () -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        if let message {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colour.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .rowMeta(AnyShapeStyle(Theme.Colour.amber))
                        .fixedSize(horizontal: false, vertical: true)
                    if let action {
                        Button(action.title, action: action.run)
                            .buttonStyle(.plain)
                            .actionLink()
                            .foregroundStyle(Theme.Colour.amber)
                            .underline()
                    }
                }
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colour.amber.opacity(0.7))
                .help(String(localized: "Dismiss"))
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colour.amberFill)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
        }
    }
}
