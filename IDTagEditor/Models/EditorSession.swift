import Foundation
import Observation
import SwiftUI
import mp3ChapterReader

@Observable
@MainActor
final class EditorSession {
    enum MediaKind {
        case mp3
        case mp4
    }

    enum SaveError: LocalizedError {
        case remoteDocument
        case invalidTag
        case missingReader
        case unsupportedEdit

        var errorDescription: String? {
            switch self {
            case .remoteDocument:
                "Only local files can be saved."
            case .invalidTag:
                "The edited ID3 tag has structural errors. Fix or discard the hex edits before saving."
            case .missingReader:
                "The edited bytes could not be parsed as an ID3 tag."
            case .unsupportedEdit:
                "This edit is not supported for this file type."
            }
        }
    }

    var mediaKind: MediaKind
    var sourceFileURL: URL
    var document: ID3TagDocument?
    var mp4Document: MP4MetadataDocument?
    var content: TagContent
    var currentTagData: Data
    var lastValidTagData: Data
    private var savedTagData: Data
    var diagnostics: [ID3ValidationDiagnostic]
    var isEditing = false
    var isDirty = false
    var statusMessage: String?
    private var didStartSecurityScopedAccess = false

    var canSave: Bool {
        isEditing && (mediaKind == .mp4 || !validation.hasFatalErrors)
    }

    var validation: ID3ValidationResult {
        ID3ValidationResult(diagnostics: diagnostics)
    }

    init(sourceFileURL: URL, mp3Data: Data, reader: mp3ChapterReader) {
        mediaKind = .mp3
        self.sourceFileURL = sourceFileURL
        didStartSecurityScopedAccess = sourceFileURL.startAccessingSecurityScopedResource()
        document = ID3TagDocument(data: mp3Data)
        content = TagContent(data: mp3Data, reader: reader)
        let tagData = TagContent.tagData(from: mp3Data, reader: reader)
        currentTagData = tagData
        lastValidTagData = tagData
        savedTagData = tagData
        diagnostics = ID3TagValidator.validate(tagData: tagData).diagnostics
    }

    init(sourceFileURL: URL, mp4Document: MP4MetadataDocument) {
        mediaKind = .mp4
        self.sourceFileURL = sourceFileURL
        didStartSecurityScopedAccess = sourceFileURL.startAccessingSecurityScopedResource()
        document = nil
        self.mp4Document = mp4Document
        content = mp4Document.content
        currentTagData = Data()
        lastValidTagData = Data()
        savedTagData = Data()
        diagnostics = []
    }

    func enableEditing() {
        isEditing = true
        statusMessage = nil
    }

    func finishEditing() {
        isEditing = false
    }

    func cancelEditing() {
        isEditing = false
        statusMessage = nil
        discardEdits()
        isDirty = false
    }

    func setTextFrame(_ id: String, value: String) {
        setTextFrame(id, toCleaned: value)
        commitStructuredEdit()
    }

    func textValue(for id: String) -> String? {
        if mediaKind == .mp4 {
            return mp4Document?.textValue(for: id)
        }

        guard let document else {
            return nil
        }

        for frame in document.frames {
            guard case .text(let frameID, let values) = frame, frameID == id else {
                continue
            }
            return values.joined(separator: " / ").nilIfEmpty
        }
        return nil
    }

    func urlValue(for id: String) -> String? {
        guard let document else {
            return nil
        }

        for frame in document.frames {
            guard case .url(let frameID, let url, _) = frame, frameID == id else {
                continue
            }
            return url.nilIfEmpty
        }
        return nil
    }

    func removeTextFrame(_ id: String) {
        guard mediaKind == .mp3 else {
            mp4Document?.setTextValue(id, value: "")
            commitStructuredEdit()
            return
        }
        guard var document else {
            return
        }
        document.removeTextFrame(id)
        self.document = document
        commitStructuredEdit()
    }

    func setURLFrame(_ id: String, url: String, description: String? = nil) {
        setURLFrame(id, toCleaned: url, description: description)
        commitStructuredEdit()
    }

    func replaceAllFrames(_ frames: [ID3MutableFrame]) {
        guard mediaKind == .mp3 else {
            statusMessage = SaveError.unsupportedEdit.localizedDescription
            return
        }
        isEditing = true
        document?.frames = frames
        commitStructuredEdit()
        statusMessage = "Replaced all tag frames. Save to write changes to disk."
    }

    func removeURLFrame(_ id: String, description: String? = nil) {
        guard mediaKind == .mp3 else {
            return
        }
        document?.removeURLFrame(id, description: description)
        commitStructuredEdit()
    }

    func replaceChapters(_ chapters: [ID3Chapter]) {
        guard mediaKind == .mp3 else {
            statusMessage = SaveError.unsupportedEdit.localizedDescription
            return
        }
        document?.replaceChapters(normalizedChapters(chapters))
        commitStructuredEdit()
    }

    func applyIdentifiedTags(_ match: ShazamID3Identifier.Match, includeLinks: Bool, artwork: ShazamID3Identifier.Artwork?) {
        guard mediaKind == .mp3, document != nil else {
            statusMessage = SaveError.unsupportedEdit.localizedDescription
            return
        }
        ShazamID3Identifier.apply(match, to: &document!, includeLinks: includeLinks, artwork: artwork)
        isEditing = true
        commitStructuredEdit()
        statusMessage = match.dialogTitle.map { "Identified \($0). Review and save the suggested tags." }
            ?? "Identified the song. Review and save the suggested tags."
    }

    func applyAlbumTags(
        albumTitle: String?,
        albumArtist: String?,
        artist: String?,
        genre: String?,
        releaseDate: String?,
        title: String?,
        trackNumber: String?,
        artwork: ShazamID3Identifier.Artwork?,
        removeArtwork: Bool = false
    ) {
        isEditing = true
        if let albumTitle {
            setTextFrame("TALB", toCleaned: albumTitle)
        }
        if let albumArtist {
            setTextFrame("TPE2", toCleaned: albumArtist)
        }
        if let artist {
            setTextFrame("TPE1", toCleaned: artist)
        }
        if let genre {
            setTextFrame("TCON", toCleaned: genre)
        }
        if let releaseDate {
            setTextFrame("TDRC", toCleaned: releaseDate)
        }
        if let title {
            setTextFrame("TIT2", toCleaned: title)
        }
        if let trackNumber {
            setTextFrame("TRCK", toCleaned: trackNumber)
        }

        if removeArtwork {
            document?.removePictureFrames()
        } else if let artwork {
            setArtworkFrame(artwork)
        }

        commitStructuredEdit()
        statusMessage = "Applied album tags. Save to write changes to disk."
    }

    var embeddedArtwork: ShazamID3Identifier.Artwork? {
        if mediaKind == .mp4 {
            return mp4Document?.artwork
        }

        guard let document else {
            return nil
        }

        for frame in document.frames {
            guard case .picture(let picture) = frame else {
                continue
            }
            return ShazamID3Identifier.Artwork(data: picture.data, mimeType: picture.mimeType)
        }

        if let frame = content.selectableFrames.first(where: { $0.frameID == "APIC" }),
           let imageData = frame.imageData {
            return ShazamID3Identifier.Artwork(data: imageData, mimeType: "image/jpeg")
        }

        return nil
    }

    func setArtwork(_ artwork: ShazamID3Identifier.Artwork) {
        isEditing = true
        setArtworkFrame(artwork)
        commitStructuredEdit()
        statusMessage = "Replaced artwork. Save to write changes to disk."
    }

    func removeArtwork() {
        isEditing = true
        if mediaKind == .mp4 {
            mp4Document?.removeArtwork()
        } else {
            document?.removePictureFrames()
        }
        commitStructuredEdit()
        statusMessage = "Removed artwork. Save to write changes to disk."
    }

    func exportArtwork(to url: URL) throws {
        guard let artwork = embeddedArtwork else {
            return
        }
        try artwork.data.write(to: url, options: .atomic)
    }

    func mergeChapters(_ importedChapters: [ID3Chapter], toleranceMilliseconds: UInt32 = 1_500) {
        var chapters = editableChapters()

        for imported in importedChapters {
            if let matchIndex = chapters.firstIndex(where: { existing in
                let a = Int64(existing.startTimeMilliseconds)
                let b = Int64(imported.startTimeMilliseconds)
                return abs(a - b) <= Int64(toleranceMilliseconds)
            }) {
                chapters[matchIndex] = imported
            } else {
                chapters.append(imported)
            }
        }

        replaceChapters(chapters)
    }

    func updateChapter(elementID: String, title: String? = nil, startTimeMilliseconds: UInt32? = nil) {
        var chapters = editableChapters()
        guard let index = chapters.firstIndex(where: { $0.elementID == elementID }) else {
            return
        }

        if let startTimeMilliseconds {
            chapters[index].startTimeMilliseconds = startTimeMilliseconds
        }

        if let title {
            chapters[index].subframes.removeAll { frame in
                if case .text(let id, _) = frame {
                    return id == "TIT2"
                }
                return false
            }
            chapters[index].subframes.insert(.text(id: "TIT2", value: title), at: 0)
        }

        replaceChapters(chapters)
    }

    func setChapterArtwork(elementID: String, artwork: ShazamID3Identifier.Artwork) {
        var chapters = editableChapters()
        guard let index = chapters.firstIndex(where: { $0.elementID == elementID }) else {
            return
        }

        chapters[index].subframes.removeAll(where: isPictureFrame(_:))
        chapters[index].subframes.append(.picture(ID3Picture(
            mimeType: artwork.mimeType,
            type: .illustration,
            description: "Chapter artwork",
            data: artwork.data
        )))
        replaceChapters(chapters)
        statusMessage = "Replaced artwork for chapter \(elementID). Save to write changes to disk."
    }

    func removeChapterArtwork(elementID: String) {
        var chapters = editableChapters()
        guard let index = chapters.firstIndex(where: { $0.elementID == elementID }) else {
            return
        }

        chapters[index].subframes.removeAll(where: isPictureFrame(_:))
        replaceChapters(chapters)
        statusMessage = "Removed artwork from chapter \(elementID). Save to write changes to disk."
    }

    func chapterTitle(elementID: String) -> String? {
        editableChapters()
            .first { $0.elementID == elementID }?
            .displayTitle
            .nilIfEmpty
    }

    func chapterStartSeconds(elementID: String) -> Double? {
        guard let chapter = editableChapters().first(where: { $0.elementID == elementID }) else {
            return nil
        }
        return Double(chapter.startTimeMilliseconds) / 1_000
    }

    func applyHexEdit(_ tagData: Data) {
        guard mediaKind == .mp3, let document else {
            return
        }

        currentTagData = tagData
        diagnostics = ID3TagValidator.validate(tagData: tagData).diagnostics
        isDirty = true

        guard !validation.hasFatalErrors else {
            statusMessage = "Hex edits contain structural ID3 errors."
            return
        }

        let mp3Data = tagData + document.audioPayload
        guard let reader = mp3ChapterReader(fromData: mp3Data) else {
            diagnostics.append(.init(severity: .error, message: "Edited bytes cannot be parsed as an ID3 tag.", byteRange: nil))
            statusMessage = "Hex edits cannot be parsed."
            return
        }

        self.document = ID3TagDocument(data: mp3Data)
        content = TagContent(data: mp3Data, reader: reader)
        lastValidTagData = tagData
        statusMessage = nil
    }

    func recalculateSizes() {
        guard mediaKind == .mp3 else {
            return
        }

        var repaired = currentTagData
        guard repaired.count >= 10 else {
            return
        }

        let version = repaired[3]
        let flags = repaired[5]
        let hasFooter = version == 4 && flags & 0x10 != 0
        let bodySize = max(0, repaired.count - 10 - (hasFooter ? 10 : 0))
        repaired.replaceSubrange(6..<10, with: synchsafeBytes(bodySize))
        applyHexEdit(repaired)
        statusMessage = validation.hasFatalErrors ? "Recalculated tag size, but structural errors remain." : "Recalculated tag size."
    }

    func rebuildFromStructuredTags() {
        guard mediaKind == .mp3 else {
            return
        }

        commitStructuredEdit(markDirty: true)
        statusMessage = "Rebuilt tag from the last valid structured tags."
    }

    func discardHexEdits() {
        guard mediaKind == .mp3 else {
            return
        }

        applyHexEdit(lastValidTagData)
        statusMessage = "Discarded invalid hex edits."
    }

    func discardEdits() {
        if mediaKind == .mp4 {
            if let mp4Document {
                Task {
                    do {
                        self.mp4Document = try await MP4MetadataDocument.load(from: mp4Document.fileURL)
                        content = self.mp4Document?.content ?? content
                        isDirty = false
                        statusMessage = "Discarded unsaved edits."
                    } catch {
                        statusMessage = error.localizedDescription
                    }
                }
            }
            return
        }

        restore(tagData: savedTagData, isDirty: false)
        statusMessage = "Discarded unsaved edits."
    }

    func restore(tagData: Data, isDirty: Bool) {
        applyHexEdit(tagData)
        self.isDirty = isDirty
        statusMessage = nil
    }

    func save() throws {
        guard canSave else {
            throw SaveError.invalidTag
        }
        try write(to: sourceFileURL)
        savedTagData = currentTagData
        isDirty = false
        statusMessage = "Saved \(sourceFileURL.lastPathComponent)."
    }

    func saveAs(to url: URL) throws {
        guard canSave else {
            throw SaveError.invalidTag
        }
        try write(to: url)
        sourceFileURL = url
        savedTagData = currentTagData
        isDirty = false
        statusMessage = "Saved \(url.lastPathComponent)."
    }

    func editableChapters() -> [ID3Chapter] {
        guard let document else {
            return []
        }

        return document.frames.compactMap { frame in
            if case .chapter(let chapter) = frame {
                return chapter
            }
            return nil
        }
    }

    private func write(to url: URL) throws {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        if mediaKind == .mp4 {
            guard var mp4Document else {
                throw SaveError.missingReader
            }
            mp4Document.fileURL = sourceFileURL
            try mp4Document.write(to: url)
            mp4Document.fileURL = url
            self.mp4Document = mp4Document
            content = mp4Document.content
        } else {
            guard let document else {
                throw SaveError.missingReader
            }
            try document.write(to: url)
        }
    }

    private func commitStructuredEdit(markDirty: Bool = true) {
        if mediaKind == .mp4 {
            if let mp4Document {
                content = mp4Document.content
            }
            isDirty = isDirty || markDirty
            statusMessage = nil
            return
        }

        do {
            guard let document else {
                throw SaveError.missingReader
            }
            let mp3Data = try document.serializedMP3Data()
            guard let reader = mp3ChapterReader(fromData: mp3Data) else {
                throw SaveError.missingReader
            }
            let tagData = TagContent.tagData(from: mp3Data, reader: reader)
            currentTagData = tagData
            lastValidTagData = tagData
            diagnostics = ID3TagValidator.validate(tagData: tagData).diagnostics
            content = TagContent(data: mp3Data, reader: reader)
            isDirty = isDirty || markDirty
            statusMessage = nil
        } catch {
            diagnostics = [.init(severity: .error, message: error.localizedDescription, byteRange: nil)]
            statusMessage = error.localizedDescription
        }
    }

    private func setTextFrame(_ id: String, toCleaned value: String) {
        if mediaKind == .mp4 {
            mp4Document?.setTextValue(id, value: value)
            return
        }

        guard var document else {
            return
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            document.removeTextFrame(id)
            self.document = document
        } else {
            replaceOrAppendFrame(.text(id: id, values: [trimmed]), matching: { frame in
                if case .text(let frameID, _) = frame {
                    return frameID == id
                }
                return false
            })
        }
    }

    private func setURLFrame(_ id: String, toCleaned value: String, description: String? = nil) {
        guard mediaKind == .mp3, var document else {
            return
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            document.removeURLFrame(id, description: description)
            self.document = document
        } else {
            replaceOrAppendFrame(.url(id: id, url: trimmed, description: description), matching: { frame in
                guard case .url(let frameID, _, let frameDescription) = frame, frameID == id else {
                    return false
                }
                return description == nil || frameDescription == description
            })
        }
    }

    private func setArtworkFrame(_ artwork: ShazamID3Identifier.Artwork) {
        if mediaKind == .mp4 {
            mp4Document?.setArtwork(artwork)
            return
        }

        guard var document else {
            return
        }

        document.setPictureFrame(ID3Picture(
            mimeType: artwork.mimeType,
            type: .coverFront,
            description: "Album artwork",
            data: artwork.data
        ))
        self.document = document
    }

    private func isPictureFrame(_ frame: ID3MutableFrame) -> Bool {
        if case .picture = frame {
            return true
        }
        return frame.id == "APIC"
    }

    private func replaceOrAppendFrame(_ replacement: ID3MutableFrame, matching predicate: (ID3MutableFrame) -> Bool) {
        guard var document else {
            return
        }

        if let index = document.frames.firstIndex(where: predicate) {
            document.frames[index] = replacement
        } else {
            document.frames.append(replacement)
        }
        self.document = document
    }

    private func normalizedChapters(_ chapters: [ID3Chapter]) -> [ID3Chapter] {
        let sorted = chapters.sorted { $0.startTimeMilliseconds < $1.startTimeMilliseconds }
        return sorted.enumerated().map { index, chapter in
            var chapter = chapter
            if index + 1 < sorted.count {
                chapter.endTimeMilliseconds = sorted[index + 1].startTimeMilliseconds
            } else if chapter.endTimeMilliseconds <= chapter.startTimeMilliseconds {
                chapter.endTimeMilliseconds = UInt32.max
            }
            if chapter.elementID.isEmpty {
                chapter.elementID = "chapter-\(index + 1)"
            }
            return chapter
        }
    }

    private func synchsafeBytes(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 21) & 0x7F),
            UInt8((value >> 14) & 0x7F),
            UInt8((value >> 7) & 0x7F),
            UInt8(value & 0x7F)
        ]
    }

}
