import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct TagBodyCard: View {
    let frame: FrameReport
    var editor: EditorSession?
    @Binding var selection: TagSelection?
    @State private var artworkOptions = ArtworkAdjustmentOptions()
    @State private var isArtworkImporterPresented = false
    @State private var artworkError: String?

    private var isEditing: Bool {
        editor?.isEditing == true
    }

    private var isSelected: Bool {
        selection?.frameSelectionID == frame.selectionID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if frame.imageData != nil {
                    ArtworkView(imageData: frame.imageData, size: 92)
                        .dropDestination(for: URL.self) { urls, _ in
                            guard let url = urls.first else {
                                return false
                            }
                            replaceArtwork(from: url)
                            return true
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(frame.tagName)
                            .font(.headline)
                            .lineLimit(2)

                        Text(frame.frameID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }

                    Text("\(frame.bodySize) bytes")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if isEditing, editableKind != .none {
                editableControl
            } else if isEditing, frame.frameID == "APIC" {
                pictureArtworkTools
            } else if !frame.summary.isEmpty {
                Text(frame.summary)
                    .font(.callout)
                    .textSelection(.enabled)
                    .lineLimit(frame.imageData == nil ? 5 : 3)
            }

            if !frame.details.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(frame.details) { detail in
                        if detail.label != "Values" || detail.value != frame.summary {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(detail.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text(detail.value)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .lineLimit(6)
                            }
                        }
                    }
                }
            }

            if let artworkError {
                Text(artworkError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .glassPanel(cornerRadius: 16)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.72), lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            selection = TagSelection(frameSelectionID: frame.selectionID, byteRange: frame.byteRange)
        }
        .fileImporter(
            isPresented: $isArtworkImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                replaceArtwork(from: url)
            }
        }
    }

    @ViewBuilder
    private var editableControl: some View {
        switch editableKind {
        case .text:
            EditableCommitTextField(
                title: frame.tagName,
                value: editor?.textValue(for: frame.frameID) ?? frame.summary,
                axis: .vertical
            ) { value in
                editor?.setTextFrame(frame.frameID, value: value)
            }
        case .url:
            EditableCommitTextField(
                title: frame.tagName,
                value: editor?.urlValue(for: frame.frameID) ?? frame.summary
            ) { value in
                editor?.setURLFrame(frame.frameID, url: value)
            }
        case .none:
            EmptyView()
        }
    }

    private var pictureArtworkTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArtworkAdjustmentControls(options: artworkOptions)
            HStack(spacing: 8) {
                Button {
                    isArtworkImporterPresented = true
                } label: {
                    Label("Replace", systemImage: "photo.badge.plus")
                }

                Button(role: .destructive) {
                    editor?.removeArtwork()
                } label: {
                    Label("Remove", systemImage: "trash")
                }

                Button {
                    exportArtwork()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(frame.imageData == nil)
            }
        }
    }

    private func replaceArtwork(from url: URL) {
        guard isEditing, frame.frameID == "APIC" else {
            return
        }

        do {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let artwork = try ArtworkProcessor.loadAdjustedArtwork(from: url, options: artworkOptions)
            editor?.setArtwork(artwork)
            artworkError = nil
        } catch {
            artworkError = error.localizedDescription
        }
    }

    private func exportArtwork() {
        #if os(macOS)
        guard let imageData = frame.imageData else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.nameFieldStringValue = "\(frame.frameID)-artwork.jpg"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try imageData.write(to: url, options: .atomic)
                artworkError = nil
            } catch {
                artworkError = error.localizedDescription
            }
        }
        #endif
    }

    private var editableKind: EditableKind {
        if frame.frameID.hasPrefix("T") {
            return .text
        }
        if frame.frameID.hasPrefix("W") {
            return .url
        }
        return .none
    }

    private enum EditableKind {
        case text
        case url
        case none
    }
}
