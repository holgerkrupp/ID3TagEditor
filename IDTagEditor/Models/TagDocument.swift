import Foundation
import mp3ChapterReader

struct TagDocument: Identifiable {
    let id = UUID()
    var displayName: String
    var sourceDescription: String
    var header: ID3HeaderReport
    var frames: [FrameReport]
    var rawTagData: Data

    var topLevelTagFrames: [FrameReport] {
        frames.filter { !$0.isChapter && !$0.isTableOfContents }
    }

    var chapters: [ChapterReport] {
        frames.compactMap(\.chapter)
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
            header: .empty(message: message),
            frames: [],
            rawTagData: Data()
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

        return TagDocument(
            displayName: url.lastPathComponent,
            sourceDescription: url.path(percentEncoded: false),
            header: ID3HeaderReport(data: data, reader: reader),
            frames: reader.frames.map(FrameReport.init(frame:)),
            rawTagData: Self.tagData(from: data, reader: reader)
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
            header: ID3HeaderReport(data: data, reader: reader),
            frames: reader.frames.map(FrameReport.init(frame:)),
            rawTagData: Self.tagData(from: data, reader: reader)
        )
    }

    private static func tagData(from data: Data, reader: mp3ChapterReader) -> Data {
        let footerSize = reader.hasFooter ? 10 : 0
        let tagByteCount = min(data.count, 10 + reader.tagSize + footerSize)
        return data.prefix(tagByteCount)
    }
}
