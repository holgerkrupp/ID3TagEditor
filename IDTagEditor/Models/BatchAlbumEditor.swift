import Foundation
import Observation
import UniformTypeIdentifiers
import mp3ChapterReader

#if os(macOS)
import AppKit
#endif

@Observable
@MainActor
final class BatchAlbumApplyOptions {
    var albumTitle = true
    var albumArtist = true
    var artist = true
    var genre = true
    var releaseDate = true
    var artwork = true
    var title = true
    var trackNumber = true

    func copy() -> BatchAlbumApplyOptionsSnapshot {
        BatchAlbumApplyOptionsSnapshot(
            albumTitle: albumTitle,
            albumArtist: albumArtist,
            artist: artist,
            genre: genre,
            releaseDate: releaseDate,
            artwork: artwork,
            title: title,
            trackNumber: trackNumber
        )
    }

    func restore(_ snapshot: BatchAlbumApplyOptionsSnapshot) {
        albumTitle = snapshot.albumTitle
        albumArtist = snapshot.albumArtist
        artist = snapshot.artist
        genre = snapshot.genre
        releaseDate = snapshot.releaseDate
        artwork = snapshot.artwork
        title = snapshot.title
        trackNumber = snapshot.trackNumber
    }
}

@Observable
@MainActor
final class BatchAlbumEditor {
    var sourceURL: URL
    var sourceName: String
    var tracks: [BatchAlbumTrack]
    var albumTitle = ""
    var albumArtist = ""
    var artist = ""
    var genre = ""
    var releaseDate = ""
    var artwork: ShazamID3Identifier.Artwork?
    var shouldRemoveArtwork = false
    var artworkOptions = ArtworkAdjustmentOptions()
    var mixedSharedFields = Set<BatchAlbumSharedField>()
    var applyOptions = BatchAlbumApplyOptions()
    var suggestions: [MusicBrainzAlbumSuggestion] = []
    var selectedSuggestionID: MusicBrainzAlbumSuggestion.ID?
    var selectedTrackIDs = Set<BatchAlbumTrack.ID>()
    var renamePattern = "{track}. {title}"
    var filenameExtractPattern = "{track} - {title}"
    var composeTargetFrameID = "TSOT"
    var composePattern = "{title}"
    var findText = ""
    var replaceText = ""
    var findReplaceUsesRegex = false
    var findReplaceFields = Set(BatchTextField.defaultSearchFields)
    var textTransform = BatchTextTransform.none
    var directoryPattern = "{albumArtist}/{album}"
    var copyTagsBuffer: [ID3MutableFrame] = []
    var podcastEpisodeURL = ""
    var podcastDescription = ""
    var podcastReleaseDate = ""
    var podcastProfileTitle = ""
    var bpmTapTimes: [Date] = []
    var statusMessage: String?
    var isIdentifying = false
    var isSaving = false
    var hasStagedTagChanges = false
    private var musicBrainzCache: [String: [MusicBrainzAlbumSuggestion]] = [:]
    private var undoStack: [BatchAlbumSnapshot] = []
    private var redoStack: [BatchAlbumSnapshot] = []

    static let multipleValuesPlaceholder = "Multiple Values"

    var selectedSuggestion: MusicBrainzAlbumSuggestion? {
        guard let selectedSuggestionID else {
            return suggestions.first
        }
        return suggestions.first { $0.id == selectedSuggestionID }
    }

    var subtitle: String {
        "\(tracks.count) MP3 file\(tracks.count == 1 ? "" : "s")"
    }

    var hasDirtyTracks: Bool {
        tracks.contains { $0.editor.isDirty }
    }

    var hasUnsavedChanges: Bool {
        hasDirtyTracks || hasStagedTagChanges
    }

    var canDiscardEdits: Bool {
        hasUnsavedChanges
    }

    var targetTracks: [BatchAlbumTrack] {
        let selected = tracks.filter { selectedTrackIDs.contains($0.id) }
        return selected.isEmpty ? tracks : selected
    }

    var selectionSummary: String {
        let count = targetTracks.count
        return selectedTrackIDs.isEmpty ? "All \(count) file\(count == 1 ? "" : "s")" : "\(count) selected file\(count == 1 ? "" : "s")"
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    init(sourceURL: URL, sourceName: String? = nil, tracks: [BatchAlbumTrack]) {
        self.sourceURL = sourceURL
        self.sourceName = sourceName ?? sourceURL.lastPathComponent
        self.tracks = tracks
        initializeSharedFields()
    }

    static func load(from folderURL: URL) throws -> BatchAlbumEditor {
        let didStartAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileURLs = try mp3Files(in: folderURL)
        let tracks = fileURLs.enumerated().compactMap { index, url in
            BatchAlbumTrack.load(from: url, index: index + 1)
        }
        return BatchAlbumEditor(sourceURL: folderURL, tracks: tracks)
    }

    static func load(fileURLs: [URL], sourceName: String = "Selected Files") -> BatchAlbumEditor {
        let tracks = fileURLs.enumerated().compactMap { index, url in
            BatchAlbumTrack.load(from: url, index: index + 1)
        }
        let sourceURL = fileURLs.first?.deletingLastPathComponent() ?? URL(fileURLWithPath: NSHomeDirectory())
        return BatchAlbumEditor(sourceURL: sourceURL, sourceName: sourceName, tracks: tracks)
    }

    static func fromDocuments(_ documents: [TagDocument]) -> BatchAlbumEditor {
        let tracks = documents.enumerated().compactMap { index, document -> BatchAlbumTrack? in
            guard let url = document.sourceURL,
                  let editor = document.editorSession else {
                return nil
            }
            editor.enableEditing()
            return BatchAlbumTrack(fileURL: url, editor: editor, index: index + 1)
        }
        let sourceURL = documents.first?.sourceURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: NSHomeDirectory())
        return BatchAlbumEditor(sourceURL: sourceURL, sourceName: "Selected Files", tracks: tracks)
    }

    func identifyAll() {
        guard !isIdentifying else {
            return
        }

        isIdentifying = true
        statusMessage = "Searching MusicBrainz for a matching release..."
        let cacheKey = musicBrainzCacheKey

        Task {
            defer {
                isIdentifying = false
            }

            do {
                let matches: [MusicBrainzAlbumSuggestion]
                let didUseCache: Bool
                if let cached = musicBrainzCache[cacheKey] {
                    matches = cached
                    didUseCache = true
                    statusMessage = "Loaded \(cached.count) cached MusicBrainz candidate\(cached.count == 1 ? "" : "s"). Choose a release to apply."
                } else {
                    matches = try await MusicBrainzClient.suggestAlbums(
                        folderName: sourceName,
                        albumTitle: albumTitle,
                        albumArtist: albumArtist,
                        artist: artist,
                        localTracks: tracks
                    )
                    musicBrainzCache[cacheKey] = matches
                    didUseCache = false
                }
                pushUndo()
                suggestions = matches
                selectedSuggestionID = matches.first?.id
                if !didUseCache {
                    statusMessage = "MusicBrainz found \(matches.count) release candidate\(matches.count == 1 ? "" : "s"). Choose a release to apply."
                }
            } catch {
                statusMessage = error.localizedDescription
                for track in tracks where track.identificationStatus == "Not identified" {
                    track.identificationStatus = "No MusicBrainz match"
                }
            }
        }
    }

    func selectSuggestion(_ suggestion: MusicBrainzAlbumSuggestion) {
        selectedSuggestionID = suggestion.id
        statusMessage = "Selected \(suggestion.title). Apply the selected candidate to update the batch fields."
    }

    func applySelectedSuggestion() {
        guard let selectedSuggestion else {
            return
        }
        pushUndo()
        apply(selectedSuggestion)
        hasStagedTagChanges = true
        statusMessage = "Applied \(selectedSuggestion.title). Review the fields, then apply checked fields and save."
    }

    func apply(_ suggestion: MusicBrainzAlbumSuggestion) {
        albumTitle = suggestion.title
        albumArtist = suggestion.artist
        artist = suggestion.artist
        genre = suggestion.genre
        releaseDate = suggestion.date
        mixedSharedFields.removeAll()
        if let suggestionArtwork = suggestion.artwork {
            artwork = suggestionArtwork
        }

        for track in tracks {
            guard let suggestedTrack = suggestion.tracks.first(where: { $0.position == Int(track.trackNumber) })
                ?? suggestion.tracks[safe: tracks.firstIndex(where: { $0.id == track.id }) ?? -1] else {
                track.identificationStatus = "No track match"
                continue
            }

            track.title = suggestedTrack.title
            track.trackNumber = suggestedTrack.number
            track.musicBrainzTrack = suggestedTrack
            track.identificationStatus = "MusicBrainz"
        }
    }

    func applyToAll() {
        pushUndo()
        for track in tracks {
            track.editor.applyAlbumTags(
                albumTitle: valueToApply(albumTitle, field: .albumTitle, isChecked: applyOptions.albumTitle),
                albumArtist: valueToApply(albumArtist, field: .albumArtist, isChecked: applyOptions.albumArtist),
                artist: valueToApply(artist, field: .artist, isChecked: applyOptions.artist),
                genre: valueToApply(genre, field: .genre, isChecked: applyOptions.genre),
                releaseDate: valueToApply(releaseDate, field: .releaseDate, isChecked: applyOptions.releaseDate),
                title: applyOptions.title ? track.title : nil,
                trackNumber: applyOptions.trackNumber ? track.trackNumber : nil,
                artwork: applyOptions.artwork && !shouldRemoveArtwork ? artwork : nil,
                removeArtwork: applyOptions.artwork && shouldRemoveArtwork
            )
        }
        hasStagedTagChanges = false
        statusMessage = "Applied album tags to \(tracks.count) file\(tracks.count == 1 ? "" : "s")."
    }

    func updateSharedField(_ field: BatchAlbumSharedField, value: String) {
        switch field {
        case .albumTitle where albumTitle != value:
            pushUndo()
            albumTitle = value
        case .albumArtist where albumArtist != value:
            pushUndo()
            albumArtist = value
        case .artist where artist != value:
            pushUndo()
            artist = value
        case .genre where genre != value:
            pushUndo()
            genre = value
        case .releaseDate where releaseDate != value:
            pushUndo()
            releaseDate = value
        default:
            return
        }
        mixedSharedFields.remove(field)
        hasStagedTagChanges = true
    }

    func updateTrackTitle(_ track: BatchAlbumTrack, value: String) {
        guard track.title != value else {
            return
        }
        pushUndo()
        track.title = value
        hasStagedTagChanges = true
    }

    func updateTrackNumber(_ track: BatchAlbumTrack, value: String) {
        guard track.trackNumber != value else {
            return
        }
        pushUndo()
        track.trackNumber = value
        hasStagedTagChanges = true
    }

    func setTrackSelected(_ track: BatchAlbumTrack, isSelected: Bool) {
        if isSelected {
            selectedTrackIDs.insert(track.id)
        } else {
            selectedTrackIDs.remove(track.id)
        }
    }

    func selectAllTracks() {
        selectedTrackIDs = Set(tracks.map(\.id))
    }

    func clearTrackSelection() {
        selectedTrackIDs.removeAll()
    }

    func setArtwork(from url: URL) {
        do {
            pushUndo()
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            artwork = try ArtworkProcessor.loadAdjustedArtwork(from: url, options: artworkOptions)
            shouldRemoveArtwork = false
            applyOptions.artwork = true
            hasStagedTagChanges = true
            statusMessage = "Loaded adjusted artwork from \(url.lastPathComponent)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func removeArtwork() {
        pushUndo()
        artwork = nil
        shouldRemoveArtwork = true
        applyOptions.artwork = true
        hasStagedTagChanges = true
        statusMessage = "Artwork will be removed when checked fields are applied."
    }

    func exportArtwork(to folderURL: URL) {
        let didStartAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        var exported = 0
        var failures: [String] = []
        for track in tracks {
            guard let artwork = track.editor.embeddedArtwork else {
                continue
            }
            let baseName = track.fileURL.deletingPathExtension().lastPathComponent
            let fileExtension = ArtworkProcessor.fileExtension(for: artwork.mimeType)
            let destination = folderURL.appendingPathComponent("\(baseName)-artwork.\(fileExtension)")
            do {
                try artwork.data.write(to: destination, options: .atomic)
                exported += 1
            } catch {
                failures.append("\(track.fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if exported == 0, failures.isEmpty {
            statusMessage = "No embedded artwork was found."
        } else if failures.isEmpty {
            statusMessage = "Exported artwork from \(exported) file\(exported == 1 ? "" : "s")."
        } else {
            statusMessage = failures.joined(separator: "\n")
        }
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else {
            return
        }
        redoStack.append(makeSnapshot())
        restore(snapshot)
        statusMessage = "Undid batch edit."
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else {
            return
        }
        undoStack.append(makeSnapshot())
        restore(snapshot)
        statusMessage = "Redid batch edit."
    }

    func discardEdits() {
        for track in tracks {
            track.editor.discardEdits()
            track.saveStatus = ""
        }
        initializeSharedFields()
        hasStagedTagChanges = false
        undoStack.removeAll()
        redoStack.removeAll()
        statusMessage = "Discarded unsaved batch edits."
    }

    func saveAll() {
        guard !isSaving else {
            return
        }

        isSaving = true
        defer {
            isSaving = false
        }

        var failures: [String] = []
        for track in tracks {
            do {
                try track.editor.save()
                track.saveStatus = "Saved"
            } catch {
                track.saveStatus = error.localizedDescription
                failures.append("\(track.fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        statusMessage = failures.isEmpty ? "Saved all files." : failures.joined(separator: "\n")
        if failures.isEmpty {
            hasStagedTagChanges = false
        }
    }

    func renamePreview() -> [BatchPreviewRow] {
        targetTracks.map { track in
            let filename = renderedPattern(renamePattern, track: track).sanitizedFilename(defaultName: track.fileURL.deletingPathExtension().lastPathComponent)
            let newName = filename.hasSuffix(".mp3") ? filename : "\(filename).mp3"
            return BatchPreviewRow(track: track, field: "Filename", current: track.fileURL.lastPathComponent, proposed: newName)
        }
    }

    func applyRenamePreview() {
        let rows = renamePreview()
        guard !rows.isEmpty else {
            return
        }
        pushUndo()
        var failures: [String] = []
        for row in rows {
            guard let track = tracks.first(where: { $0.id == row.trackID }) else {
                continue
            }
            let destination = track.fileURL.deletingLastPathComponent().appendingPathComponent(row.proposed)
            do {
                try FileManager.default.moveItem(at: track.fileURL, to: destination)
                track.fileURL = destination
                track.editor.sourceFileURL = destination
            } catch {
                failures.append("\(track.fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        statusMessage = failures.isEmpty ? "Renamed \(rows.count) file\(rows.count == 1 ? "" : "s")." : failures.joined(separator: "\n")
    }

    func filenameExtractPreview() -> [BatchPreviewRow] {
        targetTracks.flatMap { track in
            let values = extractValues(from: track.fileURL.deletingPathExtension().lastPathComponent, pattern: filenameExtractPattern)
            return values.compactMap { entry -> BatchPreviewRow? in
                let (key, value) = entry
                guard let field = BatchTextField.patternField(named: key) else {
                    return nil
                }
                return BatchPreviewRow(track: track, field: field.title, current: textValue(field, track: track), proposed: value)
            }
        }
    }

    func applyFilenameExtraction() {
        let rows = filenameExtractPreview()
        guard !rows.isEmpty else {
            statusMessage = "No filename values matched the pattern."
            return
        }
        pushUndo()
        apply(rows: rows)
        statusMessage = "Extracted tags from filenames for \(Set(rows.map(\.trackID)).count) file\(Set(rows.map(\.trackID)).count == 1 ? "" : "s")."
    }

    func composePreview() -> [BatchPreviewRow] {
        guard let field = BatchTextField(frameID: composeTargetFrameID) else {
            return []
        }
        return targetTracks.map { track in
            BatchPreviewRow(track: track, field: field.title, current: textValue(field, track: track), proposed: renderedPattern(composePattern, track: track))
        }
    }

    func applyComposeTags() {
        let rows = composePreview()
        guard !rows.isEmpty else {
            return
        }
        pushUndo()
        apply(rows: rows)
        statusMessage = "Composed \(rows.count) tag value\(rows.count == 1 ? "" : "s")."
    }

    func findReplacePreview() -> [BatchPreviewRow] {
        targetTracks.flatMap { track in
            BatchTextField.searchable.compactMap { field in
                guard findReplaceFields.contains(field), let current = track.editor.textValue(for: field.frameID) else {
                    return nil
                }
                let transformed = transformedValue(replacedValue(current))
                guard transformed != current else {
                    return nil
                }
                return BatchPreviewRow(track: track, field: field.title, current: current, proposed: transformed)
            }
        }
    }

    func applyFindReplace() {
        let rows = findReplacePreview()
        guard !rows.isEmpty else {
            statusMessage = "No matching tag values found."
            return
        }
        pushUndo()
        apply(rows: rows)
        statusMessage = "Updated \(rows.count) text tag\(rows.count == 1 ? "" : "s")."
    }

    func exportCSV(to url: URL) throws {
        let fields = BatchTextField.csvFields
        var lines = [["File"] + fields.map(\.title)]
        lines += targetTracks.map { track in
            [track.fileURL.path] + fields.map { textValue($0, track: track) }
        }
        try lines.map { $0.map(Self.csvEscaped(_:)).joined(separator: ",") }.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        statusMessage = "Exported CSV for \(targetTracks.count) file\(targetTracks.count == 1 ? "" : "s")."
    }

    func importCSV(from url: URL) throws {
        let rows = try Self.readCSV(url: url)
        guard let header = rows.first else {
            statusMessage = "CSV is empty."
            return
        }
        var previewRows: [BatchPreviewRow] = []
        for row in rows.dropFirst() {
            guard let fileIndex = header.firstIndex(where: { $0.caseInsensitiveCompare("File") == .orderedSame }),
                  row.indices.contains(fileIndex) else {
                continue
            }
            let file = row[fileIndex]
            guard let track = tracks.first(where: { $0.fileURL.path == file || $0.fileURL.lastPathComponent == URL(fileURLWithPath: file).lastPathComponent }) else {
                continue
            }
            for field in BatchTextField.csvFields {
                guard let column = header.firstIndex(where: { $0.caseInsensitiveCompare(field.title) == .orderedSame || $0.caseInsensitiveCompare(field.frameID) == .orderedSame }),
                      row.indices.contains(column) else {
                    continue
                }
                let proposed = row[column]
                let current = textValue(field, track: track)
                if proposed != current {
                    previewRows.append(BatchPreviewRow(track: track, field: field.title, current: current, proposed: proposed))
                }
            }
        }
        guard !previewRows.isEmpty else {
            statusMessage = "CSV contained no tag changes."
            return
        }
        pushUndo()
        apply(rows: previewRows)
        statusMessage = "Imported \(previewRows.count) CSV tag change\(previewRows.count == 1 ? "" : "s")."
    }

    func exportM3U(to url: URL) throws {
        let lines = ["#EXTM3U"] + targetTracks.map(\.fileURL.path)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        statusMessage = "Exported M3U playlist."
    }

    func importM3U(from url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        let urls = text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .map { URL(fileURLWithPath: $0, relativeTo: url.deletingLastPathComponent()).standardizedFileURL }
            .filter { $0.pathExtension.lowercased() == "mp3" }
        let loaded = urls.enumerated().compactMap { index, url in BatchAlbumTrack.load(from: url, index: index + 1) }
        guard !loaded.isEmpty else {
            statusMessage = "No editable MP3 files found in the playlist."
            return
        }
        pushUndo()
        tracks = loaded
        selectedTrackIDs.removeAll()
        initializeSharedFields()
        statusMessage = "Loaded \(loaded.count) playlist file\(loaded.count == 1 ? "" : "s")."
    }

    func copyTagsFromFirstTarget() {
        guard let track = targetTracks.first,
              let frames = track.editor.document?.frames else {
            return
        }
        copyTagsBuffer = frames
        statusMessage = "Copied tags from \(track.fileURL.lastPathComponent)."
    }

    func pasteCopiedTags() {
        guard !copyTagsBuffer.isEmpty else {
            statusMessage = "No copied tags available."
            return
        }
        pushUndo()
        for track in targetTracks {
            track.editor.replaceAllFrames(copyTagsBuffer)
        }
        statusMessage = "Pasted copied tags to \(targetTracks.count) file\(targetTracks.count == 1 ? "" : "s")."
    }

    func revealTargetsInFinder() {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting(targetTracks.map(\.fileURL))
        #endif
    }

    func removeTargetsFromBatch() {
        let ids = Set(targetTracks.map(\.id))
        guard !ids.isEmpty else {
            return
        }
        pushUndo()
        tracks.removeAll { ids.contains($0.id) }
        selectedTrackIDs.removeAll()
        initializeSharedFields()
        statusMessage = "Removed \(ids.count) file\(ids.count == 1 ? "" : "s") from the batch."
    }

    func deleteTargetsFromDisk() {
        let doomed = targetTracks
        guard !doomed.isEmpty else {
            return
        }
        pushUndo()
        var failures: [String] = []
        for track in doomed {
            do {
                try FileManager.default.trashItem(at: track.fileURL, resultingItemURL: nil)
            } catch {
                failures.append("\(track.fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        let failedIDs = Set(failures.compactMap { failure in doomed.first { failure.hasPrefix($0.fileURL.lastPathComponent) }?.id })
        tracks.removeAll { doomed.map(\.id).contains($0.id) && !failedIDs.contains($0.id) }
        selectedTrackIDs.removeAll()
        initializeSharedFields()
        statusMessage = failures.isEmpty ? "Moved \(doomed.count) file\(doomed.count == 1 ? "" : "s") to the Trash." : failures.joined(separator: "\n")
    }

    func moveOrCopyTargets(to folderURL: URL, copy: Bool) {
        let rows = targetTracks.map { track -> (BatchAlbumTrack, URL) in
            let directory = renderedPattern(directoryPattern, track: track).sanitizedPathComponent(defaultName: "Album")
            return (track, folderURL.appendingPathComponent(directory, isDirectory: true).appendingPathComponent(track.fileURL.lastPathComponent))
        }
        guard !rows.isEmpty else {
            return
        }
        pushUndo()
        var failures: [String] = []
        for (track, destination) in rows {
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if copy {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: track.fileURL, to: destination)
                } else {
                    try FileManager.default.moveItem(at: track.fileURL, to: destination)
                    track.fileURL = destination
                    track.editor.sourceFileURL = destination
                }
            } catch {
                failures.append("\(track.fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        statusMessage = failures.isEmpty ? "\(copy ? "Copied" : "Moved") \(rows.count) file\(rows.count == 1 ? "" : "s")." : failures.joined(separator: "\n")
    }

    func applySpecializedTags() {
        pushUndo()
        for track in targetTracks {
            if !podcastEpisodeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                track.editor.setURLFrame("WFED", url: podcastEpisodeURL)
            }
            if !podcastDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                track.editor.setTextFrame("COMM", value: podcastDescription)
            }
            if !podcastReleaseDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                track.editor.setTextFrame("TDRL", value: podcastReleaseDate.id3SafeDate)
            }
            if !podcastProfileTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                track.editor.setTextFrame("TIT1", value: podcastProfileTitle)
            }
        }
        statusMessage = "Applied specialized podcast/audiobook fields."
    }

    func tapTempo() {
        let now = Date()
        bpmTapTimes.append(now)
        bpmTapTimes = bpmTapTimes.filter { now.timeIntervalSince($0) < 8 }
        guard bpmTapTimes.count >= 2 else {
            return
        }
        let intervals = zip(bpmTapTimes.dropFirst(), bpmTapTimes).map { $0.timeIntervalSince($1) }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        let bpm = max(1, Int((60 / average).rounded()))
        pushUndo()
        for track in targetTracks {
            track.editor.setTextFrame("TBPM", value: "\(bpm)")
        }
        statusMessage = "Tapped \(bpm) BPM."
    }

    private static func mp3Files(in folderURL: URL) throws -> [URL] {
        let didStartAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "mp3" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func mimeType(for url: URL) -> String {
        ArtworkOutputFormat.jpeg.mimeType
    }

    private func initializeSharedFields() {
        albumTitle = sharedTextValue(for: "TALB", fallback: sourceName, field: .albumTitle)
        albumArtist = sharedTextValue(for: "TPE2", fallback: "", field: .albumArtist)
        artist = sharedTextValue(for: "TPE1", fallback: "", field: .artist)
        genre = sharedTextValue(for: "TCON", fallback: "", field: .genre)
        releaseDate = sharedTextValue(for: "TDRC", fallback: "", field: .releaseDate)
        artwork = nil
    }

    private func apply(rows: [BatchPreviewRow]) {
        for row in rows {
            guard let track = tracks.first(where: { $0.id == row.trackID }),
                  let field = BatchTextField(title: row.field) else {
                continue
            }
            switch field {
            case .title:
                track.title = row.proposed
            case .trackNumber:
                track.trackNumber = row.proposed
            default:
                break
            }
            track.editor.setTextFrame(field.frameID, value: row.proposed)
        }
    }

    private func renderedPattern(_ pattern: String, track: BatchAlbumTrack) -> String {
        var output = pattern
        for field in BatchTextField.patternFields {
            output = output.replacingOccurrences(of: "{\(field.token)}", with: textValue(field, track: track))
        }
        output = output.replacingOccurrences(of: "{filename}", with: track.fileURL.deletingPathExtension().lastPathComponent)
        output = output.replacingOccurrences(of: "{ext}", with: track.fileURL.pathExtension)
        return output
    }

    private func textValue(_ field: BatchTextField, track: BatchAlbumTrack) -> String {
        switch field {
        case .title:
            return track.title
        case .trackNumber:
            return track.trackNumber
        default:
            return track.editor.textValue(for: field.frameID) ?? ""
        }
    }

    private func extractValues(from filename: String, pattern: String) -> [String: String] {
        var tokens: [String] = []
        var regex = NSRegularExpression.escapedPattern(for: pattern)
        for token in BatchTextField.patternFields.map(\.token) {
            let marker = NSRegularExpression.escapedPattern(for: "{\(token)}")
            if regex.contains(marker) {
                tokens.append(token)
                regex = regex.replacingOccurrences(of: marker, with: "(.+?)")
            }
        }
        guard !tokens.isEmpty,
              let expression = try? NSRegularExpression(pattern: "^\(regex)$") else {
            return [:]
        }
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = expression.firstMatch(in: filename, range: range) else {
            return [:]
        }
        var values: [String: String] = [:]
        for (index, token) in tokens.enumerated() {
            guard let matchRange = Range(match.range(at: index + 1), in: filename) else {
                continue
            }
            values[token] = String(filename[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return values
    }

    private func replacedValue(_ value: String) -> String {
        guard !findText.isEmpty else {
            return value
        }
        if findReplaceUsesRegex, let expression = try? NSRegularExpression(pattern: findText) {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replaceText)
        }
        return value.replacingOccurrences(of: findText, with: replaceText, options: [.caseInsensitive])
    }

    private func transformedValue(_ value: String) -> String {
        switch textTransform {
        case .none:
            return value
        case .titleCase:
            return value.localizedCapitalized
        case .uppercase:
            return value.uppercased()
        case .lowercase:
            return value.lowercased()
        case .trimWhitespace:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .normalizeSpaces:
            return value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    private static func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func readCSV(url: URL) throws -> [[String]] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var iterator = text.makeIterator()
        while let character = iterator.next() {
            if character == "\"" {
                if isQuoted, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        isQuoted = false
                        if next == "," {
                            row.append(field)
                            field = ""
                        } else if next == "\n" {
                            row.append(field)
                            rows.append(row)
                            row = []
                            field = ""
                        } else {
                            field.append(next)
                        }
                    }
                } else {
                    isQuoted.toggle()
                }
            } else if character == "," && !isQuoted {
                row.append(field)
                field = ""
            } else if character == "\n" && !isQuoted {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private var musicBrainzCacheKey: String {
        [
            sourceName,
            albumTitle,
            albumArtist,
            artist,
            "\(tracks.count)",
            tracks.map { "\($0.trackNumber):\($0.title)" }.joined(separator: "|")
        ]
        .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        .joined(separator: "::")
    }

    private func sharedTextValue(for frameID: String, fallback: String, field: BatchAlbumSharedField) -> String {
        let values = tracks.map { $0.editor.textValue(for: frameID) ?? "" }
        guard let first = values.first else {
            return fallback
        }
        if values.allSatisfy({ $0 == first }) {
            mixedSharedFields.remove(field)
            return first.nilIfEmpty ?? fallback
        }
        mixedSharedFields.insert(field)
        return ""
    }

    private func valueToApply(_ value: String, field: BatchAlbumSharedField, isChecked: Bool) -> String? {
        guard isChecked else {
            return nil
        }
        if mixedSharedFields.contains(field), value.isEmpty {
            return nil
        }
        return value
    }

    private func pushUndo() {
        undoStack.append(makeSnapshot())
        redoStack.removeAll()
    }

    private func makeSnapshot() -> BatchAlbumSnapshot {
        BatchAlbumSnapshot(
            albumTitle: albumTitle,
            albumArtist: albumArtist,
            artist: artist,
            genre: genre,
            releaseDate: releaseDate,
            artwork: artwork,
            shouldRemoveArtwork: shouldRemoveArtwork,
            artworkOptions: artworkOptions.snapshot(),
            mixedSharedFields: mixedSharedFields,
            applyOptions: applyOptions.copy(),
            tracks: tracks.map(BatchAlbumTrackSnapshot.init(track:)),
            suggestions: suggestions,
            selectedSuggestionID: selectedSuggestionID,
            hasStagedTagChanges: hasStagedTagChanges,
            statusMessage: statusMessage
        )
    }

    private func restore(_ snapshot: BatchAlbumSnapshot) {
        albumTitle = snapshot.albumTitle
        albumArtist = snapshot.albumArtist
        artist = snapshot.artist
        genre = snapshot.genre
        releaseDate = snapshot.releaseDate
        artwork = snapshot.artwork
        shouldRemoveArtwork = snapshot.shouldRemoveArtwork
        artworkOptions.restore(snapshot.artworkOptions)
        mixedSharedFields = snapshot.mixedSharedFields
        applyOptions.restore(snapshot.applyOptions)
        suggestions = snapshot.suggestions
        selectedSuggestionID = snapshot.selectedSuggestionID
        hasStagedTagChanges = snapshot.hasStagedTagChanges
        statusMessage = snapshot.statusMessage

        for trackSnapshot in snapshot.tracks {
            guard let track = tracks.first(where: { $0.id == trackSnapshot.id }) else {
                continue
            }
            track.restore(trackSnapshot)
        }
    }
}

enum BatchAlbumSharedField: Hashable {
    case albumTitle
    case albumArtist
    case artist
    case genre
    case releaseDate
}

struct BatchPreviewRow: Identifiable {
    let id = UUID()
    var trackID: BatchAlbumTrack.ID
    var fileName: String
    var field: String
    var current: String
    var proposed: String

    init(track: BatchAlbumTrack, field: String, current: String, proposed: String) {
        trackID = track.id
        fileName = track.fileURL.lastPathComponent
        self.field = field
        self.current = current
        self.proposed = proposed
    }
}

enum BatchTextTransform: String, CaseIterable, Identifiable {
    case none = "None"
    case titleCase = "Title Case"
    case uppercase = "Uppercase"
    case lowercase = "Lowercase"
    case trimWhitespace = "Trim Whitespace"
    case normalizeSpaces = "Normalize Spaces"

    var id: String { rawValue }
}

enum BatchTextField: String, CaseIterable, Identifiable, Hashable {
    case title = "TIT2"
    case album = "TALB"
    case artist = "TPE1"
    case albumArtist = "TPE2"
    case genre = "TCON"
    case releaseDate = "TDRC"
    case trackNumber = "TRCK"
    case discNumber = "TPOS"
    case composer = "TCOM"
    case titleSort = "TSOT"
    case albumSort = "TSOA"
    case artistSort = "TSOP"
    case lyrics = "USLT"
    case comment = "COMM"
    case bpm = "TBPM"
    case grouping = "TIT1"
    case subtitle = "TIT3"
    case publisher = "TPUB"
    case copyright = "TCOP"
    case podcastURL = "WFED"
    case releaseTime = "TDRL"

    var id: String { frameID }
    var frameID: String { rawValue }

    var title: String {
        switch self {
        case .title: "Title"
        case .album: "Album"
        case .artist: "Artist"
        case .albumArtist: "Album Artist"
        case .genre: "Genre"
        case .releaseDate: "Recording Date"
        case .trackNumber: "Track"
        case .discNumber: "Disc"
        case .composer: "Composer"
        case .titleSort: "Title Sort"
        case .albumSort: "Album Sort"
        case .artistSort: "Artist Sort"
        case .lyrics: "Lyrics"
        case .comment: "Comment"
        case .bpm: "BPM"
        case .grouping: "Grouping"
        case .subtitle: "Subtitle"
        case .publisher: "Publisher"
        case .copyright: "Copyright"
        case .podcastURL: "Episode URL"
        case .releaseTime: "Release Date"
        }
    }

    var token: String {
        switch self {
        case .title: "title"
        case .album: "album"
        case .artist: "artist"
        case .albumArtist: "albumArtist"
        case .genre: "genre"
        case .releaseDate: "date"
        case .trackNumber: "track"
        case .discNumber: "disc"
        case .composer: "composer"
        case .titleSort: "sortTitle"
        case .albumSort: "sortAlbum"
        case .artistSort: "sortArtist"
        case .lyrics: "lyrics"
        case .comment: "comment"
        case .bpm: "bpm"
        case .grouping: "grouping"
        case .subtitle: "subtitle"
        case .publisher: "publisher"
        case .copyright: "copyright"
        case .podcastURL: "episodeURL"
        case .releaseTime: "releaseDate"
        }
    }

    static let patternFields: [BatchTextField] = [.trackNumber, .title, .album, .artist, .albumArtist, .genre, .releaseDate, .discNumber, .composer, .titleSort, .albumSort, .artistSort]
    static let defaultSearchFields: [BatchTextField] = [.title, .album, .artist, .albumArtist, .genre, .composer, .titleSort, .albumSort, .artistSort, .lyrics, .comment]
    static let searchable: [BatchTextField] = [.title, .album, .artist, .albumArtist, .genre, .releaseDate, .trackNumber, .discNumber, .composer, .titleSort, .albumSort, .artistSort, .lyrics, .comment, .bpm, .grouping, .subtitle, .publisher, .copyright]
    static let csvFields: [BatchTextField] = [.title, .album, .artist, .albumArtist, .genre, .releaseDate, .trackNumber, .discNumber, .composer, .titleSort, .albumSort, .artistSort, .lyrics, .comment, .bpm, .grouping, .subtitle, .publisher, .copyright, .podcastURL, .releaseTime]

    init?(frameID: String) {
        self.init(rawValue: frameID)
    }

    init?(title: String) {
        let lowered = title.lowercased()
        guard let field = Self.allCases.first(where: { $0.title.lowercased() == lowered || $0.frameID.lowercased() == lowered }) else {
            return nil
        }
        self = field
    }

    static func patternField(named token: String) -> BatchTextField? {
        patternFields.first { $0.token == token }
    }
}

struct BatchAlbumApplyOptionsSnapshot {
    var albumTitle: Bool
    var albumArtist: Bool
    var artist: Bool
    var genre: Bool
    var releaseDate: Bool
    var artwork: Bool
    var title: Bool
    var trackNumber: Bool
}

struct BatchAlbumSnapshot {
    var albumTitle: String
    var albumArtist: String
    var artist: String
    var genre: String
    var releaseDate: String
    var artwork: ShazamID3Identifier.Artwork?
    var shouldRemoveArtwork: Bool
    var artworkOptions: ArtworkAdjustmentSnapshot
    var mixedSharedFields: Set<BatchAlbumSharedField>
    var applyOptions: BatchAlbumApplyOptionsSnapshot
    var tracks: [BatchAlbumTrackSnapshot]
    var suggestions: [MusicBrainzAlbumSuggestion]
    var selectedSuggestionID: MusicBrainzAlbumSuggestion.ID?
    var hasStagedTagChanges: Bool
    var statusMessage: String?
}

struct BatchAlbumTrackSnapshot {
    var id: BatchAlbumTrack.ID
    var title: String
    var trackNumber: String
    var musicBrainzTrack: MusicBrainzAlbumSuggestion.Track?
    var identificationStatus: String
    var saveStatus: String
    var editorTagData: Data
    var editorIsDirty: Bool

    init(track: BatchAlbumTrack) {
        id = track.id
        title = track.title
        trackNumber = track.trackNumber
        musicBrainzTrack = track.musicBrainzTrack
        identificationStatus = track.identificationStatus
        saveStatus = track.saveStatus
        editorTagData = track.editor.currentTagData
        editorIsDirty = track.editor.isDirty
    }
}

@Observable
@MainActor
final class BatchAlbumTrack: Identifiable {
    let id = UUID()
    var fileURL: URL
    var editor: EditorSession
    var title: String
    var trackNumber: String
    var musicBrainzTrack: MusicBrainzAlbumSuggestion.Track?
    var identificationStatus = "Not identified"
    var saveStatus = ""

    init(fileURL: URL, editor: EditorSession, index: Int) {
        self.fileURL = fileURL
        self.editor = editor
        title = editor.textValue(for: "TIT2") ?? fileURL.deletingPathExtension().lastPathComponent
        trackNumber = editor.textValue(for: "TRCK") ?? "\(index)"
    }

    static func load(from url: URL, index: Int) -> BatchAlbumTrack? {
        do {
            let data = try Data(contentsOf: url)
            guard let reader = mp3ChapterReader(fromData: data) else {
                return nil
            }
            let editor = EditorSession(sourceFileURL: url, mp3Data: data, reader: reader)
            editor.enableEditing()
            return BatchAlbumTrack(fileURL: url, editor: editor, index: index)
        } catch {
            return nil
        }
    }

    func restore(_ snapshot: BatchAlbumTrackSnapshot) {
        title = snapshot.title
        trackNumber = snapshot.trackNumber
        musicBrainzTrack = snapshot.musicBrainzTrack
        identificationStatus = snapshot.identificationStatus
        saveStatus = snapshot.saveStatus
        editor.restore(tagData: snapshot.editorTagData, isDirty: snapshot.editorIsDirty)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    func sanitizedFilename(defaultName: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? defaultName : cleaned
    }

    func sanitizedPathComponent(defaultName: String) -> String {
        let components = split(separator: "/")
            .map { String($0).sanitizedFilename(defaultName: defaultName) }
            .filter { !$0.isEmpty }
        return components.isEmpty ? defaultName : components.joined(separator: "/")
    }

    var id3SafeDate: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^\d{4}(-\d{2}(-\d{2})?)?$"#, options: .regularExpression) != nil {
            return trimmed
        }
        return String(trimmed.prefix(10))
    }
}
