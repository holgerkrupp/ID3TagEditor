import Foundation
import mp3ChapterReader

struct TagContent {
    var header: ID3HeaderReport
    var frames: [FrameReport]
    var rawTagData: Data

    var topLevelTagFrames: [FrameReport] {
        frames.filter { !$0.isChapter && !$0.isTableOfContents }
    }

    var chapters: [ChapterReport] {
        frames.compactMap(\.chapter)
    }

    var selectableFrames: [FrameReport] {
        frames.flatMap { frame in
            [frame] + frame.flattenedChildren
        }
    }

    @MainActor
    init(data: Data, reader: mp3ChapterReader) {
        header = ID3HeaderReport(data: data, reader: reader)
        rawTagData = Self.tagData(from: data, reader: reader)
        let frameRanges = Self.frameByteRanges(in: rawTagData)
        frames = reader.frames.enumerated().map { index, frame in
            let range = index < frameRanges.count ? frameRanges[index] : nil
            return FrameReport(
                frame: frame,
                selectionID: "\(range?.id ?? frame.frameID)@\(range?.range.lowerBound ?? index)",
                byteRange: range?.range,
                childByteRanges: range?.childRanges ?? []
            )
        }
    }

    init(header: ID3HeaderReport, frames: [FrameReport], rawTagData: Data) {
        self.header = header
        self.frames = frames
        self.rawTagData = rawTagData
    }

    static func empty(message: String) -> TagContent {
        TagContent(header: .empty(message: message), frames: [], rawTagData: Data())
    }

    static func tagData(from data: Data, reader: mp3ChapterReader) -> Data {
        let footerSize = reader.hasFooter ? 10 : 0
        let tagByteCount = min(data.count, 10 + reader.tagSize + footerSize)
        return data.prefix(tagByteCount)
    }

    static func frameByteRanges(in data: Data) -> [FrameByteRange] {
        guard data.count >= 10, data.prefix(3) == Data("ID3".utf8) else {
            return []
        }

        let version = Int(data[3])
        let flags = data[5]
        let declaredBodySize = readSynchsafeInt(data, at: 6)
        var offset = 10
        let frameLimit = min(data.count, 10 + declaredBodySize)

        if flags & 0x40 != 0 {
            guard offset + 4 <= frameLimit else {
                return []
            }
            let extendedSize = version == 4 ? readSynchsafeInt(data, at: offset) : readUInt32BigEndian(data, at: offset) + 4
            guard extendedSize > 0, offset + extendedSize <= frameLimit else {
                return []
            }
            offset += extendedSize
        }

        return readFrameByteRanges(data: data, offset: offset, limit: frameLimit, version: version)
    }

    private static func readFrameByteRanges(data: Data, offset: Int, limit: Int, version: Int) -> [FrameByteRange] {
        let headerSize = version == 2 ? 6 : 10
        let idSize = version == 2 ? 3 : 4
        var offset = offset
        var ranges: [FrameByteRange] = []

        while offset + headerSize <= limit {
            let idRange = offset..<(offset + idSize)
            if data[idRange].allSatisfy({ $0 == 0 }) {
                break
            }

            guard let frameID = String(data: data[idRange], encoding: .ascii), frameID.count == idSize else {
                break
            }

            let bodySize: Int
            if version == 2 {
                bodySize = readUInt24BigEndian(data, at: offset + 3)
            } else if version == 4 {
                bodySize = readSynchsafeInt(data, at: offset + 4)
            } else {
                bodySize = readUInt32BigEndian(data, at: offset + 4)
            }

            guard bodySize >= 0 else {
                break
            }

            let bodyStart = offset + headerSize
            let bodyEnd = bodyStart + bodySize
            guard bodyEnd <= limit else {
                break
            }

            let childRanges = childFrameByteRanges(frameID: frameID, data: data, bodyStart: bodyStart, bodyEnd: bodyEnd, version: version)
            ranges.append(FrameByteRange(id: frameID, range: offset..<bodyEnd, childRanges: childRanges))
            offset = bodyEnd
        }

        return ranges
    }

    private static func childFrameByteRanges(frameID: String, data: Data, bodyStart: Int, bodyEnd: Int, version: Int) -> [FrameByteRange] {
        guard frameID == "CHAP" || frameID == "CTOC" else {
            return []
        }

        guard let elementTerminator = data[bodyStart..<bodyEnd].firstIndex(of: 0) else {
            return []
        }

        var childStart: Int
        if frameID == "CHAP" {
            childStart = elementTerminator + 1 + 16
        } else {
            childStart = elementTerminator + 1 + 2
            guard childStart <= bodyEnd else {
                return []
            }
            let childCount = Int(data[childStart - 1])
            for _ in 0..<childCount {
                guard childStart < bodyEnd,
                      let terminator = data[childStart..<bodyEnd].firstIndex(of: 0) else {
                    return []
                }
                childStart = terminator + 1
            }
        }

        guard childStart < bodyEnd else {
            return []
        }

        return readFrameByteRanges(data: data, offset: childStart, limit: bodyEnd, version: version)
    }
}

private func readUInt24BigEndian(_ data: Data, at offset: Int) -> Int {
    guard offset + 2 < data.count else {
        return 0
    }
    return (Int(data[offset]) << 16) | (Int(data[offset + 1]) << 8) | Int(data[offset + 2])
}
