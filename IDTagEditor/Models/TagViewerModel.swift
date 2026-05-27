import SwiftUI

#if os(macOS)
import AppKit
#endif

@Observable
@MainActor
final class TagViewerModel {
    private enum PendingSaveAction {
        case activeItem
        case selectedDocumentAs
        case batchAlbum
    }

    var documents: [TagDocument] = []
    var selectedID: TagDocument.ID?
    var selectedIDs = Set<TagDocument.ID>() {
        didSet {
            selectedID = selectedIDs.first
        }
    }
    var batchEditor: BatchAlbumEditor?
    var isImporterPresented = false
    var isSavePaywallPresented = false
    var alertMessage: String?
    var isIdentifyingSelectedDocument = false
    let saveUnlockStore = SaveUnlockStore()
    private var pendingSaveAction: PendingSaveAction?

    var selectedDocument: TagDocument? {
        if batchEditor != nil {
            return nil
        }
        let activeSelection = selectedIDs.count == 1 ? selectedIDs.first : selectedID
        guard let selectedID = activeSelection else {
            return documents.first
        }
        return documents.first { $0.id == selectedID }
    }

    var selectedDocuments: [TagDocument] {
        documents.filter { selectedIDs.contains($0.id) }
    }

    func openFileImporter() {
        isImporterPresented = true
    }

    var canSaveActiveItem: Bool {
        if let batchEditor {
            return batchEditor.hasDirtyTracks && !batchEditor.isSaving
        }
        return selectedDocument?.editorSession?.canSave == true && selectedDocument?.editorSession?.isDirty == true
    }

    var hasUnsavedChanges: Bool {
        if let batchEditor {
            return batchEditor.hasDirtyTracks
        }
        return documents.contains { $0.editorSession?.isDirty == true }
    }

    var canSaveSelectedDocumentAs: Bool {
        selectedDocument?.editorSession?.canSave == true
    }

    var canIdentifySelectedDocument: Bool {
        selectedDocument?.canEdit == true && !isIdentifyingSelectedDocument
    }

    var canToggleSelectedDocumentEditing: Bool {
        selectedDocument?.canEdit == true
    }

    var canRunBatchActions: Bool {
        batchEditor != nil || selectedDocuments.filter(\.canEdit).count > 1
    }

    var selectedDocumentIsEditing: Bool {
        selectedDocument?.editorSession?.isEditing == true
    }

    var shouldShowSaveUnlock: Bool {
        !saveUnlockStore.isUnlocked
    }

    func saveActiveItem() {
        guard ensureSaveUnlocked(for: .activeItem) else {
            return
        }
        performSaveActiveItem()
    }

    func showSaveUnlock() {
        pendingSaveAction = nil
        isSavePaywallPresented = true
    }

    func handleSaveUnlockPaywallDismissed() {
        isSavePaywallPresented = false

        guard saveUnlockStore.isUnlocked, let pendingSaveAction else {
            self.pendingSaveAction = nil
            return
        }

        self.pendingSaveAction = nil

        switch pendingSaveAction {
        case .activeItem:
            performSaveActiveItem()
        case .selectedDocumentAs:
            performSaveSelectedDocumentAs()
        case .batchAlbum:
            performSaveBatchAlbum()
        }
    }

    private func ensureSaveUnlocked(for action: PendingSaveAction) -> Bool {
        guard !saveUnlockStore.isUnlocked else {
            return true
        }

        pendingSaveAction = action
        isSavePaywallPresented = true
        return false
    }

    private func performSaveActiveItem() {
        if let batchEditor {
            batchEditor.saveAll()
        } else {
            saveSelectedDocument()
        }
    }

    func identifyBatchAlbum() {
        ensureBatchEditorFromSelection()
        batchEditor?.identifyAll()
    }

    func applyBatchTags() {
        ensureBatchEditorFromSelection()
        batchEditor?.applyToAll()
    }

    func saveBatchAlbum() {
        guard ensureSaveUnlocked(for: .batchAlbum) else {
            return
        }
        performSaveBatchAlbum()
    }

    private func performSaveBatchAlbum() {
        batchEditor?.saveAll()
    }

    func recalculateSelectedTagSizes() {
        selectedDocument?.editorSession?.recalculateSizes()
    }

    func rebuildSelectedTagFromStructuredTags() {
        selectedDocument?.editorSession?.rebuildFromStructuredTags()
    }

    func discardSelectedHexEdits() {
        selectedDocument?.editorSession?.discardHexEdits()
    }

    func toggleEditing(for document: TagDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }),
              let editor = documents[index].editorSession else {
            return
        }

        if editor.isEditing {
            editor.cancelEditing()
        } else {
            editor.enableEditing()
        }
    }

    func saveSelectedDocument() {
        guard let editor = selectedDocument?.editorSession else {
            return
        }

        do {
            try editor.save()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func saveSelectedDocumentAs() {
        guard ensureSaveUnlocked(for: .selectedDocumentAs) else {
            return
        }
        performSaveSelectedDocumentAs()
    }

    private func performSaveSelectedDocumentAs() {
        #if os(macOS)
        guard let editor = selectedDocument?.editorSession else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mp3]
        panel.nameFieldStringValue = editor.sourceFileURL.lastPathComponent
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try editor.saveAs(to: url)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
        #endif
    }

    func identifySelectedDocument() {
        guard !isIdentifyingSelectedDocument,
              let document = selectedDocument,
              let editor = document.editorSession else {
            return
        }

        isIdentifyingSelectedDocument = true
        Task {
            defer {
                isIdentifyingSelectedDocument = false
            }

            do {
                let didStartAccess = editor.sourceFileURL.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess {
                        editor.sourceFileURL.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: editor.sourceFileURL)
                let match = try await ShazamID3Identifier.identify(mp3Data: data, filename: editor.sourceFileURL.lastPathComponent)
                let artwork = await artwork(for: match)
                editor.applyIdentifiedTags(match, includeLinks: true, artwork: artwork)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            load(urls)
        case .failure(let error):
            documents.insert(.failed(source: "File import", error: error), at: 0)
            selectedID = documents.first?.id
        }
    }

    func load(_ urls: [URL]) {
        let folders = urls.filter(isFolder)
        let fileURLs = urls.filter { $0.isFileURL && !isFolder($0) }

        if folders.isEmpty, fileURLs.count > 1 {
            let batch = BatchAlbumEditor.load(fileURLs: fileURLs)
            if batch.tracks.isEmpty {
                documents.insert(.message(source: "Selected Files", message: "No editable MP3 files with ID3 tags were found in the selected files."), at: 0)
                selectedID = documents.first?.id
                selectedIDs = Set(documents.prefix(1).map(\.id))
                batchEditor = nil
            } else {
                batchEditor = batch
                selectedID = nil
                selectedIDs = []
            }
            return
        }

        for url in urls {
            load(url)
        }
    }

    func load(_ url: URL) {
        if isFolder(url) {
            loadFolder(url)
            return
        }

        Task {
            let document = await TagDocument.load(from: url)
            documents.insert(document, at: 0)
            selectedID = document.id
            selectedIDs = [document.id]
            batchEditor = nil
        }
    }

    func loadFolder(_ url: URL) {
        Task {
            do {
                let batch = try BatchAlbumEditor.load(from: url)
                if batch.tracks.isEmpty {
                    documents.insert(.message(source: url.lastPathComponent, message: "No editable MP3 files with ID3 tags were found in this folder."), at: 0)
                    selectedID = documents.first?.id
                    selectedIDs = Set(documents.prefix(1).map(\.id))
                    batchEditor = nil
                } else {
                    batchEditor = batch
                    selectedID = nil
                    selectedIDs = []
                }
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func loadFromPasteboard() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            load(urls)
            return
        }

        if let string = pasteboard.string(forType: .string) {
            let candidates = string
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .compactMap(URL.init(string:))

            if !candidates.isEmpty {
                load(candidates)
                return
            }
        }

        documents.insert(.message(source: "Pasteboard", message: "No MP3 file or URL was found on the pasteboard."), at: 0)
        selectedID = documents.first?.id
        selectedIDs = Set(documents.prefix(1).map(\.id))
        #endif
    }

    func startBatchEditingSelectedDocuments() {
        ensureBatchEditorFromSelection()
    }

    private func ensureBatchEditorFromSelection() {
        guard batchEditor == nil else {
            return
        }
        let editableDocuments = selectedDocuments.filter(\.canEdit)
        guard editableDocuments.count > 1 else {
            return
        }
        batchEditor = BatchAlbumEditor.fromDocuments(editableDocuments)
        selectedID = nil
    }

    private func artwork(for match: ShazamID3Identifier.Match) async -> ShazamID3Identifier.Artwork? {
        guard let artworkURL = match.artworkURL else {
            return nil
        }
        return try? await ShazamID3Identifier.fetchArtwork(from: artworkURL)
    }

    private func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
