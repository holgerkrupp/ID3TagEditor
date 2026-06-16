import AVFoundation
import CoreMedia
import Foundation

struct MP4MetadataDocument {
    enum MetadataError: LocalizedError {
        case cannotCreateExportSession
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .cannotCreateExportSession:
                "This file cannot be exported with updated MPEG-4 metadata."
            case .exportFailed:
                "The MPEG-4 metadata export failed."
            }
        }
    }

    var fileURL: URL
    var fileSize: Int
    var originalMetadata: [AVMetadataItem]
    var fields: [MP4MetadataField]
    var artwork: ShazamID3Identifier.Artwork?

    var content: TagContent {
        TagContent(
            header: .mediaFile(kind: "MPEG-4/AAC", fileSize: fileSize, metadataCount: fields.count),
            frames: fields.map(FrameReport.init(mp4Field:)),
            rawTagData: Data()
        )
    }

    static func load(from url: URL) async throws -> MP4MetadataDocument {
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        let asset = AVURLAsset(url: url)
        let metadata = try await loadMetadata(from: asset)
        let fields = await MP4MetadataField.editableFields(from: metadata)

        return MP4MetadataDocument(
            fileURL: url,
            fileSize: resourceValues.fileSize ?? 0,
            originalMetadata: metadata,
            fields: fields,
            artwork: fields.first(where: { $0.kind == .artwork })?.artwork
        )
    }

    private static func loadMetadata(from asset: AVAsset) async throws -> [AVMetadataItem] {
        async let commonMetadata = asset.load(.commonMetadata)
        async let metadata = asset.load(.metadata)
        let formats = try await asset.load(.availableMetadataFormats)

        var items = try await commonMetadata + metadata
        for format in formats {
            items.append(contentsOf: try await asset.loadMetadata(for: format))
        }

        var seen = Set<String>()
        return items.filter { item in
            let identity = [
                item.identifier?.rawValue ?? "",
                item.keySpace?.rawValue ?? "",
                String(describing: item.key)
            ].joined(separator: "|")
            return seen.insert(identity).inserted
        }
    }

    func textValue(for id: String) -> String? {
        fields.first { $0.id == id }?.value.nilIfEmpty
    }

    mutating func setTextValue(_ id: String, value: String) {
        guard let kind = MP4MetadataKind(id: id), kind != .artwork else {
            return
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = fields.firstIndex(where: { $0.id == id }) {
            if trimmed.isEmpty {
                fields.remove(at: index)
            } else {
                fields[index].value = trimmed
            }
        } else if !trimmed.isEmpty {
            fields.append(MP4MetadataField(kind: kind, value: trimmed))
        }
    }

    mutating func setArtwork(_ artwork: ShazamID3Identifier.Artwork) {
        self.artwork = artwork
        if let index = fields.firstIndex(where: { $0.kind == .artwork }) {
            fields[index].artwork = artwork
            fields[index].value = "\(artwork.mimeType), \(artwork.data.count) bytes"
        } else {
            fields.append(MP4MetadataField(kind: .artwork, artwork: artwork))
        }
    }

    mutating func removeArtwork() {
        artwork = nil
        fields.removeAll { $0.kind == .artwork }
    }

    func write(to url: URL) throws {
        let asset = AVURLAsset(url: fileURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw MetadataError.cannotCreateExportSession
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension.isEmpty ? fileURL.pathExtension : url.pathExtension)
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        exportSession.outputURL = temporaryURL
        exportSession.outputFileType = outputFileType(for: url)
        exportSession.metadata = mergedMetadata()
        exportSession.exportSynchronously()

        if let error = exportSession.error {
            throw error
        }

        guard exportSession.status == .completed else {
            throw MetadataError.exportFailed
        }

        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            _ = try FileManager.default.replaceItemAt(
                url,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }

    private func mergedMetadata() -> [AVMetadataItem] {
        let editableIdentifiers = Set(MP4MetadataKind.allCases.flatMap(\.identifiers))
        let preserved = originalMetadata.filter { item in
            guard let identifier = item.identifier else {
                return true
            }
            return !editableIdentifiers.contains(identifier)
        }
        return preserved + fields.compactMap(\.metadataItem)
    }

    private func outputFileType(for url: URL) -> AVFileType {
        switch url.pathExtension.lowercased() {
        case "m4a", "aac":
            return .m4a
        default:
            return .mp4
        }
    }
}

struct MP4MetadataField {
    var kind: MP4MetadataKind
    var value: String
    var sourceIdentifier: AVMetadataIdentifier?
    var artwork: ShazamID3Identifier.Artwork?

    var id: String { kind.id }
    var displayName: String { kind.displayName }
    var summary: String { value }

    init(kind: MP4MetadataKind, value: String = "", sourceIdentifier: AVMetadataIdentifier? = nil, artwork: ShazamID3Identifier.Artwork? = nil) {
        self.kind = kind
        self.value = value
        self.sourceIdentifier = sourceIdentifier
        self.artwork = artwork
    }

    init(kind: MP4MetadataKind, artwork: ShazamID3Identifier.Artwork) {
        self.init(kind: kind, value: "\(artwork.mimeType), \(artwork.data.count) bytes", artwork: artwork)
    }

    static func editableFields(from metadata: [AVMetadataItem]) async -> [MP4MetadataField] {
        var fields: [MP4MetadataField] = []

        for kind in MP4MetadataKind.allCases {
            guard let item = metadata.first(where: { item in
                guard let identifier = item.identifier else {
                    return false
                }
                return kind.identifiers.contains(identifier)
            }) else {
                continue
            }

            if kind == .artwork {
                if let artwork = await artwork(from: item) {
                    fields.append(MP4MetadataField(kind: kind, artwork: artwork))
                }
            } else if let value = await textValue(from: item)?.nilIfEmpty {
                fields.append(MP4MetadataField(kind: kind, value: value, sourceIdentifier: item.identifier))
            }
        }

        return fields
    }

    var metadataItem: AVMetadataItem? {
        guard kind != .artwork else {
            guard let artwork else {
                return nil
            }
            let item = AVMutableMetadataItem()
            item.identifier = kind.preferredIdentifier
            item.value = artwork.data as NSData
            item.dataType = artwork.mimeType == "image/png" ? kCMMetadataBaseDataType_PNG as String : kCMMetadataBaseDataType_JPEG as String
            return item.copy() as? AVMetadataItem
        }

        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let item = AVMutableMetadataItem()
        item.identifier = sourceIdentifier ?? kind.preferredIdentifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item.copy() as? AVMetadataItem
    }

    private static func textValue(from item: AVMetadataItem) async -> String? {
        if let string = try? await item.load(.stringValue) {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let value = try? await item.load(.value) else {
            return nil
        }
        return describe(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func artwork(from item: AVMetadataItem) async -> ShazamID3Identifier.Artwork? {
        let data: Data?
        if let loadedData = try? await item.load(.dataValue) {
            data = loadedData
        } else if let value = try? await item.load(.value) {
            data = value as? Data ?? (value as? NSData).map(Data.init(referencing:))
        } else {
            data = nil
        }

        guard let data else {
            return nil
        }
        let mimeType = item.dataType == kCMMetadataBaseDataType_PNG as String ? "image/png" : "image/jpeg"
        return ShazamID3Identifier.Artwork(data: data, mimeType: mimeType)
    }
}

enum MP4MetadataKind: String, CaseIterable {
    case title
    case artist
    case album
    case genre
    case year
    case description
    case copyright
    case artwork

    init?(id: String) {
        self.init(rawValue: id)
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .genre: "Genre"
        case .year: "Year"
        case .description: "Description"
        case .copyright: "Copyright"
        case .artwork: "Artwork"
        }
    }

    var preferredIdentifier: AVMetadataIdentifier {
        identifiers[0]
    }

    var identifiers: [AVMetadataIdentifier] {
        switch self {
        case .title:
            [.commonIdentifierTitle, .quickTimeMetadataTitle]
        case .artist:
            [.commonIdentifierArtist, .commonIdentifierAuthor, .quickTimeMetadataArtist, .quickTimeMetadataPerformer]
        case .album:
            [.commonIdentifierAlbumName, .quickTimeMetadataAlbum]
        case .genre:
            [.quickTimeMetadataGenre]
        case .year:
            [.quickTimeMetadataYear, .commonIdentifierCreationDate]
        case .description:
            [.commonIdentifierDescription, .quickTimeMetadataDescription, .quickTimeMetadataInformation]
        case .copyright:
            [.commonIdentifierCopyrights, .quickTimeMetadataCopyright]
        case .artwork:
            [.commonIdentifierArtwork]
        }
    }
}

private extension AVAssetExportSession {
    func exportSynchronously() {
        let semaphore = DispatchSemaphore(value: 0)
        exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()
    }
}
