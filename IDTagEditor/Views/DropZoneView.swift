import SwiftUI

struct DropZoneView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)

            Text("Drop MP3 files or URLs")
                .font(.headline)

            Text("Paste works with copied files, file URLs, and HTTP URLs.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .glassPanel(cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop MP3 files or URLs")
        .accessibilityHint("Drop files here, or use Open or Paste from the toolbar.")
    }
}
