import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct DocumentHeaderView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let document: TagDocument
    let isIdentifyingWithShazam: Bool
    @State private var artworkOptions = ArtworkAdjustmentOptions()
    @State private var isArtworkImporterPresented = false
    @State private var artworkError: String?

    var body: some View {
        (horizontalSizeClass == .compact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))) {
            VStack(alignment: .leading, spacing: 8) {
                Text(document.displayName)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(2)

                Text(document.sourceDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if let editor = document.editorSession, editor.isEditing {
                    HStack(spacing: 8) {
                        Label(editor.isDirty ? "Editing" : "Edit mode", systemImage: "pencil")
                        if editor.validation.hasFatalErrors {
                            Label("Fix tag before saving", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                        if let statusMessage = editor.statusMessage {
                            Text(statusMessage)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                } else if document.isRemote {
                    Label("Remote files are read-only", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isIdentifyingWithShazam {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Identifying with Shazam...")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Identifying with Shazam")
                }

                if let artworkError {
                    Text(artworkError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if horizontalSizeClass != .compact {
                Spacer(minLength: 20)
            }

            VStack(alignment: horizontalSizeClass == .compact ? .leading : .trailing, spacing: 10) {
                ArtworkView(
                    imageData: document.editorSession?.embeddedArtwork?.data ?? document.topLevelTagFrames.first(where: { $0.frameID == "APIC" })?.imageData,
                    size: 104,
                    accessibilityLabel: "Embedded artwork for \(document.displayName)"
                )
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first else {
                            return false
                        }
                        replaceArtwork(from: url)
                        return true
                    }
                    .controlHelp(document.canEdit ? "Drop artwork here to replace embedded artwork." : "Embedded artwork.")

                Text(document.header.versionString)
                    .font(.title3.weight(.semibold))

                Text(ByteCountFormatter.id3.string(fromByteCount: Int64(document.header.fileSize)))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if document.canEdit {
                    DisclosureGroup("Artwork") {
                        VStack(alignment: .trailing, spacing: 10) {
                            ArtworkAdjustmentControls(options: artworkOptions)
                            HStack(spacing: 8) {
                                Button {
                                    isArtworkImporterPresented = true
                                } label: {
                                    Label("Replace", systemImage: "photo.badge.plus")
                                }
                                .controlHelp("Choose replacement artwork from disk.")

                                Button(role: .destructive) {
                                    document.editorSession?.removeArtwork()
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .controlHelp("Remove embedded artwork from this file.")

                                Button {
                                    exportArtwork()
                                } label: {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }
                                .disabled(document.editorSession?.embeddedArtwork == nil)
                                .controlHelp("Export the embedded artwork to an image file.")
                            }
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 430, alignment: horizontalSizeClass == .compact ? .leading : .trailing)
                    .accessibilityLabel("Artwork tools")
                }
            }
        }
        .padding(horizontalSizeClass == .compact ? 16 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 26)
        .accessibilityElement(children: .contain)
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

    private func replaceArtwork(from url: URL) {
        guard document.canEdit else {
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
            document.editorSession?.setArtwork(artwork)
            artworkError = nil
        } catch {
            artworkError = error.localizedDescription
        }
    }

    private func exportArtwork() {
        #if os(macOS)
        guard let artwork = document.editorSession?.embeddedArtwork else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ArtworkProcessor.fileExtension(for: artwork.mimeType)) ?? .jpeg]
        panel.nameFieldStringValue = "\(document.displayName)-artwork.\(ArtworkProcessor.fileExtension(for: artwork.mimeType))"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try artwork.data.write(to: url, options: .atomic)
                artworkError = nil
            } catch {
                artworkError = error.localizedDescription
            }
        }
        #endif
    }
}
