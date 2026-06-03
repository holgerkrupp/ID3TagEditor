import Foundation
import AVFoundation
import mp3ChapterReader

struct FrameReport: Identifiable {
    let id = UUID()
    var frameID: String
    var originalID: String
    var tagName: String
    var headerSize: Int
    var bodySize: Int
    var totalSize: Int
    var summary: String
    var flagsSummary: String
    var details: [FrameDetail]
    var children: [FrameReport]
    var imageData: Data?
    var chapter: ChapterReport?
    var selectionID: String
    var byteRange: Range<Int>?

    var isChapter: Bool { chapter != nil }
    var isTableOfContents: Bool { frameID == "CTOC" }
    var flattenedChildren: [FrameReport] {
        children.flatMap { child in
            [child] + child.flattenedChildren
        }
    }

    @MainActor
    init(frame: Frame, selectionID: String? = nil, byteRange: Range<Int>? = nil, childByteRanges: [FrameByteRange] = []) {
        frameID = frame.frameID
        originalID = frame.originalFrameID
        tagName = ID3FrameNames.name(for: frame.frameID)
        headerSize = frame.originalFrameID.count == 3 ? 6 : 10
        bodySize = frame.size
        totalSize = headerSize + bodySize
        flagsSummary = frame.flags.summary
        imageData = (frame as? PictureFrame)?.image
        self.byteRange = byteRange
        self.selectionID = selectionID ?? "\(frame.frameID)@\(byteRange?.lowerBound ?? -1)"
        let parsedDetails = FrameReport.details(for: frame)
        let parsedChildren = FrameReport.children(for: frame, parentSelectionID: self.selectionID, ranges: childByteRanges)
        let parsedChapter: ChapterReport?
        if let chapterFrame = frame as? ChapFrame {
            parsedChapter = ChapterReport(
                chapter: chapterFrame,
                children: parsedChildren,
                selectionID: self.selectionID,
                byteRange: byteRange
            )
        } else {
            parsedChapter = nil
        }
        details = parsedDetails
        children = parsedChildren
        chapter = parsedChapter
        summary = FrameReport.summary(for: frame, details: parsedDetails, chapter: parsedChapter)
    }

    init(mp4Field field: MP4MetadataField) {
        frameID = field.id
        originalID = field.sourceIdentifier?.rawValue ?? field.kind.preferredIdentifier.rawValue
        tagName = field.displayName
        headerSize = 0
        bodySize = field.artwork?.data.count ?? field.value.utf8.count
        totalSize = bodySize
        summary = field.summary
        flagsSummary = "MPEG-4 metadata"
        details = [
            FrameDetail("Identifier", originalID),
            FrameDetail("Value", field.summary)
        ].filter { !$0.value.isEmpty }
        children = []
        imageData = field.artwork?.data
        chapter = nil
        selectionID = "mp4/\(field.id)"
        byteRange = nil
    }

    private static func summary(for frame: Frame, details: [FrameDetail], chapter: ChapterReport?) -> String {
        if let chapter {
            return "\(chapter.title) · \(chapter.timeRange)"
        }

        if let text = frame as? TextFrame {
            return text.values.joined(separator: " / ")
        }

        if let link = frame as? LinkFrame {
            return [link.descriptionText, link.urlString].compactMap { $0 }.joined(separator: " - ")
        }

        if let picture = frame as? PictureFrame {
            return [picture.type?.description, picture.mimeType].compactMap { $0 }.joined(separator: " - ")
        }

        if let toc = frame as? CTOCFrame {
            return "\(toc.elementID) · \(toc.childElementIDs.count) child elements"
        }

        return details.first?.value ?? "Raw frame data"
    }

    private static func details(for frame: Frame) -> [FrameDetail] {
        var rows: [FrameDetail] = []

        switch frame {
        case let text as TextFrame:
            rows.append(.init("Encoding", text.textEncoding.description))
            rows.append(.init("Values", text.values.joined(separator: "\n")))
        case let credits as CreditsFrame:
            rows.append(.init("Encoding", credits.textEncoding.description))
            rows.append(.init("Credits", credits.pairs.map { "\($0["role"] ?? ""): \($0["name"] ?? "")" }.joined(separator: "\n")))
        case let link as LinkFrame:
            rows.append(.init("User defined", link.userDefined.yesNo))
            rows.append(.init("Description", link.descriptionText ?? ""))
            rows.append(.init("URL", link.urlString ?? ""))
        case let picture as PictureFrame:
            rows.append(.init("MIME type", picture.mimeType ?? ""))
            rows.append(.init("Type", picture.type?.description ?? ""))
            rows.append(.init("Description", picture.descriptionText ?? ""))
            rows.append(.init("Image size", "\(picture.image?.count ?? 0) bytes"))
        case let chapter as ChapFrame:
            rows.append(.init("Element ID", chapter.elementID))
            rows.append(.init("Start time", "\(chapter.startTime / 1000) seconds"))
            rows.append(.init("End time", "\(chapter.endTime / 1000) seconds"))
            rows.append(.init("Start offset", chapter.startOffset.id3OffsetDescription))
            rows.append(.init("End offset", chapter.endOffset.id3OffsetDescription))
        case let toc as CTOCFrame:
            rows.append(.init("Element ID", toc.elementID))
            rows.append(.init("Top level", toc.isTopLevel.yesNo))
            rows.append(.init("Ordered", toc.isOrdered.yesNo))
            rows.append(.init("Children", toc.childElementIDs.joined(separator: "\n")))
        case let structured as StructuredFrame:
            rows.append(contentsOf: structured.details.sorted { $0.key < $1.key }.map { key, value in
                FrameDetail(key, describe(value))
            })
        default:
            rows.append(.init("Raw body", "\(frame.rawBody.count) bytes"))
        }

        return rows.filter { !$0.value.isEmpty }
    }

    @MainActor
    private static func children(for frame: Frame, parentSelectionID: String, ranges: [FrameByteRange]) -> [FrameReport] {
        if let chapter = frame as? ChapFrame {
            return chapter.frames.enumerated().map { index, child in
                let range = index < ranges.count ? ranges[index] : nil
                return FrameReport(
                    frame: child,
                    selectionID: "\(parentSelectionID)/\(range?.id ?? child.frameID)@\(range?.range.lowerBound ?? index)",
                    byteRange: range?.range,
                    childByteRanges: range?.childRanges ?? []
                )
            }
        }

        if let toc = frame as? CTOCFrame {
            return toc.frames.enumerated().map { index, child in
                let range = index < ranges.count ? ranges[index] : nil
                return FrameReport(
                    frame: child,
                    selectionID: "\(parentSelectionID)/\(range?.id ?? child.frameID)@\(range?.range.lowerBound ?? index)",
                    byteRange: range?.range,
                    childByteRanges: range?.childRanges ?? []
                )
            }
        }

        return []
    }
}

struct FrameDetail: Identifiable {
    let id = UUID()
    var label: String
    var value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

struct ChapterReport: Identifiable {
    let id = UUID()
    var elementID: String
    var title: String
    var subtitle: String
    var startTime: Double
    var endTime: Double
    var startOffset: Int
    var endOffset: Int
    var link: String?
    var imageData: Data?
    var embeddedFrames: [FrameReport]
    var selectionID: String
    var byteRange: Range<Int>?

    var timeRange: String {
        "\(formatTime(startTime)) - \(formatTime(endTime))"
    }

    var duration: String {
        formatTime(max(0, endTime - startTime))
    }

    init(chapter: ChapFrame, children: [FrameReport], selectionID: String, byteRange: Range<Int>?) {
        elementID = chapter.elementID
        startTime = chapter.startTime / 1000
        endTime = chapter.endTime / 1000
        startOffset = chapter.startOffset
        endOffset = chapter.endOffset
        embeddedFrames = children
        self.selectionID = selectionID
        self.byteRange = byteRange
        title = children.first { $0.frameID == "TIT2" }?.summary.nilIfEmpty ?? chapter.elementID
        subtitle = children.first { $0.frameID == "TIT3" }?.summary ?? ""
        link = children.first { $0.frameID.hasPrefix("W") }?.summary.nilIfEmpty
        imageData = children.first(where: { $0.imageData != nil })?.imageData
    }
}
