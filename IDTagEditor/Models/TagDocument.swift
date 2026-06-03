import Foundation
import mp3ChapterReader
import UniformTypeIdentifiers

struct TagDocument: Identifiable {
    let id = UUID()
    var displayName: String
    var sourceDescription: String
    var sourceURL: URL?
    var isRemote: Bool
    var content: TagContent
    var editorSession: EditorSession?

    var header: ID3HeaderReport {
        presentedContent.header
    }

    var frames: [FrameReport] {
        presentedContent.frames
    }

    var rawTagData: Data {
        presentedContent.rawTagData
    }

    var topLevelTagFrames: [FrameReport] {
        presentedContent.topLevelTagFrames
    }

    var chapters: [ChapterReport] {
        presentedContent.chapters
    }

    var selectableFrames: [FrameReport] {
        presentedContent.selectableFrames
    }

    var canEdit: Bool {
        !isRemote && sourceURL != nil && editorSession != nil
    }

    var supportsID3ByteInspection: Bool {
        editorSession?.mediaKind != .mp4
    }

    var presentedContent: TagContent {
        editorSession?.content ?? content
    }

    @MainActor
    static func load(from url: URL) async -> TagDocument {
        do {
            if url.isFileURL {
                return try await loadLocal(url)
            }
            return try await loadRemote(url)
        } catch {
            return .failed(source: url.absoluteString, error: error)
        }
    }

    static func failed(source: String, error: Error) -> TagDocument {
        message(source: source, message: error.localizedDescription)
    }

    static func message(source: String, message: String) -> TagDocument {
        TagDocument(
            displayName: "Unable to read ID3 tag",
            sourceDescription: source,
            sourceURL: nil,
            isRemote: true,
            content: .empty(message: message),
            editorSession: nil
        )
    }

    @MainActor
    private static func loadLocal(_ url: URL) async throws -> TagDocument {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if isMPEG4AudioOrVideo(url) {
            let mp4Document = try await MP4MetadataDocument.load(from: url)
            return TagDocument(
                displayName: url.lastPathComponent,
                sourceDescription: url.path(percentEncoded: false),
                sourceURL: url,
                isRemote: false,
                content: mp4Document.content,
                editorSession: EditorSession(sourceFileURL: url, mp4Document: mp4Document)
            )
        }

        let data = try Data(contentsOf: url)
        guard let reader = mp3ChapterReader(fromData: data) else {
            throw TagReadError.noID3Tag
        }

        let content = TagContent(data: data, reader: reader)
        return TagDocument(
            displayName: url.lastPathComponent,
            sourceDescription: url.path(percentEncoded: false),
            sourceURL: url,
            isRemote: false,
            content: content,
            editorSession: EditorSession(sourceFileURL: url, mp3Data: data, reader: reader)
        )
    }

    private static func isMPEG4AudioOrVideo(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .mpeg4Audio)
            || type.conforms(to: .mpeg4Movie)
            || ["m4a", "m4b", "mp4", "aac"].contains(url.pathExtension.lowercased())
    }

    @MainActor
    private static func loadRemote(_ url: URL) async throws -> TagDocument {
        let data = try await RemoteID3TagFetcher.fetchID3Tag(from: url)
        guard let reader = mp3ChapterReader(fromData: data) else {
            throw TagReadError.noID3Tag
        }

        return TagDocument(
            displayName: url.lastPathComponent.isEmpty ? url.host() ?? "Remote MP3" : url.lastPathComponent,
            sourceDescription: url.absoluteString,
            sourceURL: nil,
            isRemote: true,
            content: TagContent(data: data, reader: reader),
            editorSession: nil
        )
    }
}
