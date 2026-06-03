import Foundation
import mp3ChapterReader

struct ID3HeaderReport {
    var identifier: String
    var version: Int
    var revision: Int
    var flagsByte: UInt8
    var hasUnsynchronization: Bool
    var hasExtendedHeader: Bool
    var isExperimental: Bool
    var hasFooter: Bool
    var isCompressedTag: Bool
    var headerSize: Int
    var tagBodySize: Int
    var extendedHeaderSize: Int
    var footerSize: Int
    var totalTagSize: Int
    var audioStartOffset: Int
    var fileSize: Int
    var rawHeaderHex: String

    var versionString: String {
        if identifier != "ID3" {
            return identifier
        }
        return version > 0 ? "ID3v2.\(version).\(revision)" : "Unknown"
    }

    var flagsByteHex: String {
        String(format: "0x%02X", flagsByte)
    }

    init(data: Data, reader: mp3ChapterReader) {
        identifier = data.count >= 3 ? String(data: data.prefix(3), encoding: .ascii) ?? "Unknown" : "Unknown"
        version = reader.version
        revision = reader.revision
        flagsByte = data.count > 5 ? data[5] : 0
        hasUnsynchronization = reader.hasUnsynchronization
        hasExtendedHeader = reader.hasExtendedHeader
        isExperimental = reader.isExperimental
        hasFooter = reader.hasFooter
        isCompressedTag = reader.isCompressedTag
        headerSize = 10
        tagBodySize = reader.tagSize
        extendedHeaderSize = Self.extendedHeaderSize(in: data, version: reader.version, hasExtendedHeader: reader.hasExtendedHeader)
        footerSize = reader.hasFooter ? 10 : 0
        totalTagSize = headerSize + tagBodySize + footerSize
        audioStartOffset = min(totalTagSize, data.count)
        fileSize = data.count
        rawHeaderHex = data.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    init(
        identifier: String,
        version: Int,
        revision: Int,
        flagsByte: UInt8,
        hasUnsynchronization: Bool,
        hasExtendedHeader: Bool,
        isExperimental: Bool,
        hasFooter: Bool,
        isCompressedTag: Bool,
        headerSize: Int,
        tagBodySize: Int,
        extendedHeaderSize: Int,
        footerSize: Int,
        totalTagSize: Int,
        audioStartOffset: Int,
        fileSize: Int,
        rawHeaderHex: String
    ) {
        self.identifier = identifier
        self.version = version
        self.revision = revision
        self.flagsByte = flagsByte
        self.hasUnsynchronization = hasUnsynchronization
        self.hasExtendedHeader = hasExtendedHeader
        self.isExperimental = isExperimental
        self.hasFooter = hasFooter
        self.isCompressedTag = isCompressedTag
        self.headerSize = headerSize
        self.tagBodySize = tagBodySize
        self.extendedHeaderSize = extendedHeaderSize
        self.footerSize = footerSize
        self.totalTagSize = totalTagSize
        self.audioStartOffset = audioStartOffset
        self.fileSize = fileSize
        self.rawHeaderHex = rawHeaderHex
    }

    static func empty(message: String) -> ID3HeaderReport {
        ID3HeaderReport(
            identifier: message,
            version: 0,
            revision: 0,
            flagsByte: 0,
            hasUnsynchronization: false,
            hasExtendedHeader: false,
            isExperimental: false,
            hasFooter: false,
            isCompressedTag: false,
            headerSize: 0,
            tagBodySize: 0,
            extendedHeaderSize: 0,
            footerSize: 0,
            totalTagSize: 0,
            audioStartOffset: 0,
            fileSize: 0,
            rawHeaderHex: ""
        )
    }

    static func mediaFile(kind: String, fileSize: Int, metadataCount: Int) -> ID3HeaderReport {
        ID3HeaderReport(
            identifier: kind,
            version: 0,
            revision: 0,
            flagsByte: 0,
            hasUnsynchronization: false,
            hasExtendedHeader: false,
            isExperimental: false,
            hasFooter: false,
            isCompressedTag: false,
            headerSize: 0,
            tagBodySize: metadataCount,
            extendedHeaderSize: 0,
            footerSize: 0,
            totalTagSize: 0,
            audioStartOffset: 0,
            fileSize: fileSize,
            rawHeaderHex: ""
        )
    }

    private static func extendedHeaderSize(in data: Data, version: Int, hasExtendedHeader: Bool) -> Int {
        guard hasExtendedHeader, data.count >= 14 else {
            return 0
        }

        if version == 4 {
            return readSynchsafeInt(data, at: 10)
        }

        if version == 3 {
            return readUInt32BigEndian(data, at: 10) + 4
        }

        return 0
    }
}
