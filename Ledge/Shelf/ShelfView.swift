import SwiftUI

struct ShelfView: View {
    /// Temporary probe target for Task 1 only; replaced by real data in Task 13.
    private let probeURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Downloads/ledge-drag-probe.txt")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Downloads")
                .font(.headline)
            Divider()
            HStack {
                Image(systemName: "doc")
                Text(probeURL.lastPathComponent)
            }
            .padding(6)
            .contentShape(Rectangle())
            .onDrag { NSItemProvider(contentsOf: probeURL) ?? NSItemProvider() }
        }
        .padding(12)
        .frame(width: 320)
    }
}
