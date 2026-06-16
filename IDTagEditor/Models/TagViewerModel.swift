import OSLog
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
@MainActor
final class TagViewerModel {
    private static let saveLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "de.holgerkrupp.IDTagEditor",
        category: "SaveFlow"
    )
    private static let recentDocumentsDefaultsKey = "TagViewerModel.recentDocuments"
    private static let recentDocumentsLimit = 10

    private enum PendingSaveAction {
        case activeItem
        case selectedDocumentAs
        case batchAlbum
        case finishEditing(TagDocument.ID)

        var logName: String {
            switch self {
            case .activeItem:
                "Save"
            case .selectedDocumentAs:
                "Save As"
            case .batchAlbum:
                "Batch Save"
            case .finishEditing:
                "Finish Editing"
            }
        }
    }

    private struct RecentDocumentRecord: Codable, Hashable {
        let path: String
        let bookmarkData: Data

        init?(fileURL: URL) {
            guard fileURL.isFileURL else {
                return nil
            }

            path = fileURL.standardizedFileURL.resolvingSymlinksInPath().path

            do {
                bookmarkData = try fileURL.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                return nil
            }
        }

        func resolvedURL() -> URL? {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolvedURL
            }

            return URL(fileURLWithPath: path)
        }

        func matches(_ url: URL) -> Bool {
            path == url.standardizedFileURL.resolvingSymlinksInPath().path
        }
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

    func restoreRecentlyOpenedFiles() async {
        guard documents.isEmpty else {
            return
        }

        let records = loadRecentDocumentRecords()
        guard !records.isEmpty else {
            return
        }

        var restoredDocuments: [TagDocument] = []
        var validRecords: [RecentDocumentRecord] = []

        for record in records {
            guard let url = record.resolvedURL() else {
                continue
            }

            let document = await TagDocument.load(from: url)
            guard let sourceURL = document.sourceURL, sourceURL.isFileURL else {
                continue
            }

            restoredDocuments.append(document)
            validRecords.append(record)
        }

        guard !restoredDocuments.isEmpty else {
            return
        }

        documents = restoredDocuments
        selectedID = restoredDocuments.first?.id
        if let firstDocument = restoredDocuments.first {
            selectedIDs = [firstDocument.id]
        } else {
            selectedIDs = []
        }

        if validRecords.count != records.count {
            saveRecentDocumentRecords(validRecords)
        }
    }

    var canSaveActiveItem: Bool {
        if let batchEditor {
            return batchEditor.hasDirtyTracks && !batchEditor.isSaving
        }
        return selectedDocument?.editorSession?.canSave == true && selectedDocument?.editorSession?.isDirty == true
    }

    var hasUnsavedChanges: Bool {
        if let batchEditor {
            return batchEditor.hasUnsavedChanges
        }
        return documents.contains { $0.editorSession?.isDirty == true }
    }

    var canSaveSelectedDocumentAs: Bool {
        selectedDocument?.editorSession?.canSave == true
    }

    var canDiscardActiveEdits: Bool {
        if let batchEditor {
            return batchEditor.canDiscardEdits
        }
        return selectedDocument?.editorSession?.isDirty == true
    }

    var canIdentifySelectedDocument: Bool {
        selectedDocument?.canEdit == true && selectedDocument?.editorSession?.mediaKind == .mp3 && !isIdentifyingSelectedDocument
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
        Self.saveLogger.notice("PAYWALL PRESENTED: User selected Unlock Saving.")
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
        case .finishEditing(let documentID):
            performFinishEditing(documentID: documentID)
        }
    }

    private func ensureSaveUnlocked(for action: PendingSaveAction) -> Bool {
        guard !saveUnlockStore.isUnlocked else {
            Self.saveLogger.notice(
                "PAYWALL BYPASSED: \(action.logName, privacy: .public) would show the paywall, but saving is already unlocked."
            )
            return true
        }

        Self.saveLogger.notice(
            "PAYWALL PRESENTED: \(action.logName, privacy: .public) requires the save unlock purchase."
        )
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
        Self.saveLogger.notice("SAVE FINISHED: Batch save attempt completed.")
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

    func discardActiveEdits() {
        if let batchEditor {
            batchEditor.discardEdits()
        } else {
            selectedDocument?.editorSession?.discardEdits()
        }
    }

    func toggleEditing(for document: TagDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }),
              let editor = documents[index].editorSession else {
            return
        }

        if editor.isEditing {
            dismissFocusedEditor()
            Task {
                await Task.yield()
                finishEditing(documentID: document.id)
            }
        } else {
            editor.enableEditing()
        }
    }

    private func finishEditing(documentID: TagDocument.ID) {
        guard let editor = documents.first(where: { $0.id == documentID })?.editorSession,
              editor.isEditing else {
            return
        }

        guard editor.isDirty else {
            editor.finishEditing()
            return
        }

        guard ensureSaveUnlocked(for: .finishEditing(documentID)) else {
            return
        }

        performFinishEditing(documentID: documentID)
    }

    private func performFinishEditing(documentID: TagDocument.ID) {
        guard let editor = documents.first(where: { $0.id == documentID })?.editorSession else {
            return
        }

        do {
            try editor.save()
            editor.finishEditing()
            Self.saveLogger.notice(
                "SAVE SUCCEEDED: Finished editing and saved \(editor.sourceFileURL.lastPathComponent, privacy: .public)."
            )
        } catch {
            Self.saveLogger.error(
                "SAVE FAILED: \(editor.sourceFileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            alertMessage = error.localizedDescription
        }
    }

    private func dismissFocusedEditor() {
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #else
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    func saveSelectedDocument() {
        guard let editor = selectedDocument?.editorSession else {
            return
        }

        do {
            try editor.save()
            Self.saveLogger.notice(
                "SAVE SUCCEEDED: Saved \(editor.sourceFileURL.lastPathComponent, privacy: .public)."
            )
        } catch {
            Self.saveLogger.error(
                "SAVE FAILED: \(editor.sourceFileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
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
        panel.allowedContentTypes = editor.mediaKind == .mp4 ? [.mpeg4Audio, .mpeg4Movie] : [.mp3]
        panel.nameFieldStringValue = editor.sourceFileURL.lastPathComponent
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try editor.saveAs(to: url)
                Self.saveLogger.notice(
                    "SAVE SUCCEEDED: Save As wrote \(url.lastPathComponent, privacy: .public)."
                )
            } catch {
                Self.saveLogger.error(
                    "SAVE FAILED: Save As for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
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

            if let sourceURL = document.sourceURL {
                rememberRecentlyOpenedFile(sourceURL)
            }
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
        #else
        if UIPasteboard.general.hasURLs, let url = UIPasteboard.general.url {
            load(url)
            return
        }

        if let string = UIPasteboard.general.string {
            let candidates = string
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .compactMap(URL.init(string:))
            if !candidates.isEmpty {
                load(candidates)
                return
            }
        }

        documents.insert(.message(source: "Pasteboard", message: "No audio file or URL was found on the pasteboard."), at: 0)
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

    private func loadRecentDocumentRecords() -> [RecentDocumentRecord] {
        guard let data = UserDefaults.standard.data(forKey: Self.recentDocumentsDefaultsKey) else {
            return []
        }

        return (try? JSONDecoder().decode([RecentDocumentRecord].self, from: data)) ?? []
    }

    private func saveRecentDocumentRecords(_ records: [RecentDocumentRecord]) {
        guard let data = try? JSONEncoder().encode(Array(records.prefix(Self.recentDocumentsLimit))) else {
            return
        }

        UserDefaults.standard.set(data, forKey: Self.recentDocumentsDefaultsKey)
    }

    private func rememberRecentlyOpenedFile(_ url: URL) {
        guard let record = RecentDocumentRecord(fileURL: url) else {
            return
        }

        var records = loadRecentDocumentRecords()
        records.removeAll { $0.matches(url) }
        records.insert(record, at: 0)
        saveRecentDocumentRecords(records)
    }

    private func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
