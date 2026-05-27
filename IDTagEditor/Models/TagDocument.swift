import Foundation
import mp3ChapterReader

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
        !isRemote && sourceURL != nil && !content.rawTagData.isEmpty && editorSession != nil
    }

    var presentedContent: TagContent {
        editorSession?.content ?? content
    }

    @MainActor
    static func load(from url: URL) async -> TagDocument {
        do {
            if url.isFileURL {
                return try loadLocal(url)
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
    private static func loadLocal(_ url: URL) throws -> TagDocument {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
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
