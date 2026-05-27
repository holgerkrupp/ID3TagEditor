import Foundation
import mp3ChapterReader

struct ChapterImportResult: Sendable {
    var chapters: [ID3Chapter]
    var errors: [String]
}

actor ChapterImportParser {
    static let shared = ChapterImportParser()

    func parse(data: Data, filename: String) -> ChapterImportResult {
        let lowercasedName = filename.lowercased()
        if lowercasedName.hasSuffix(".xml") || String(data: data.prefix(80), encoding: .utf8)?.contains("<psc:chapters") == true {
            return PodloveSimpleChaptersParser(data: data).parse()
        }

        return ChapterImportParser.parsePlainText(String(data: data, encoding: .utf8) ?? "")
    }

    nonisolated static func parsePlainText(_ text: String) -> ChapterImportResult {
        var chapters: [ID3Chapter] = []
        var errors: [String] = []

        for (lineIndex, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            let pieces = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard pieces.count == 2, let milliseconds = parseTimecode(String(pieces[0])) else {
                errors.append("Line \(lineIndex + 1): Expected a timecode followed by a chapter title.")
                continue
            }

            let title = String(pieces[1]).trimmingCharacters(in: .whitespaces)
            chapters.append(.init(
                elementID: "chapter-\(chapters.count + 1)",
                startTimeMilliseconds: milliseconds,
                endTimeMilliseconds: milliseconds,
                subframes: [.text(id: "TIT2", value: title)]
            ))
        }

        return ChapterImportResult(chapters: normalize(chapters), errors: errors)
    }

    nonisolated static func parseTimecode(_ value: String) -> UInt32? {
        let parts = value.split(separator: ":").map(String.init)
        guard (1...3).contains(parts.count) else {
            return nil
        }

        let secondsPart = parts.last ?? "0"
        let secondPieces = secondsPart.split(separator: ".", maxSplits: 1).map(String.init)
        guard let seconds = Double(secondPieces.first ?? "") else {
            return nil
        }

        let minutes = parts.count >= 2 ? Double(parts[parts.count - 2]) ?? .nan : 0
        let hours = parts.count == 3 ? Double(parts[0]) ?? .nan : 0
        guard minutes.isFinite, hours.isFinite else {
            return nil
        }

        let total = hours * 3_600 + minutes * 60 + seconds
        guard total.isFinite, total >= 0 else {
            return nil
        }
        return UInt32(clamping: Int((total * 1_000).rounded()))
    }

    nonisolated static func normalize(_ chapters: [ID3Chapter]) -> [ID3Chapter] {
        let sorted = chapters.sorted { $0.startTimeMilliseconds < $1.startTimeMilliseconds }
        return sorted.enumerated().map { index, chapter in
            var chapter = chapter
            chapter.elementID = chapter.elementID.isEmpty ? "chapter-\(index + 1)" : chapter.elementID
            chapter.endTimeMilliseconds = index + 1 < sorted.count ? sorted[index + 1].startTimeMilliseconds : max(chapter.endTimeMilliseconds, chapter.startTimeMilliseconds)
            return chapter
        }
    }
}

nonisolated private final class PodloveSimpleChaptersParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var chapters: [ID3Chapter] = []
    private var errors: [String] = []

    init(data: Data) {
        self.data = data
    }

    func parse() -> ChapterImportResult {
        let parser = XMLParser(data: data)
        parser.delegate = self
        if !parser.parse(), let error = parser.parserError {
            errors.append(error.localizedDescription)
        }
        return ChapterImportResult(chapters: ChapterImportParser.normalize(chapters), errors: errors)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let normalizedName = (qName ?? elementName).lowercased()
        guard normalizedName.hasSuffix("chapter") else {
            return
        }

        guard let start = attributeDict["start"].flatMap(ChapterImportParser.parseTimecode) else {
            errors.append("Chapter \(chapters.count + 1): Missing or invalid start time.")
            return
        }

        let title = attributeDict["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        var subframes: [ID3MutableFrame] = [.text(id: "TIT2", value: title?.isEmpty == false ? title! : "Chapter \(chapters.count + 1)")]

        if let href = attributeDict["href"], !href.isEmpty {
            subframes.append(.url(id: "WXXX", url: href, description: "Chapter Link"))
        }

        if let image = attributeDict["image"], !image.isEmpty {
            subframes.append(.url(id: "WXXX", url: image, description: "Chapter Image"))
        }

        chapters.append(.init(
            elementID: "chapter-\(chapters.count + 1)",
            startTimeMilliseconds: start,
            endTimeMilliseconds: start,
            subframes: subframes
        ))
    }
}

extension ID3Chapter {
    nonisolated var displayTitle: String {
        for frame in subframes {
            if case .text(let id, let values) = frame, id == "TIT2" {
                return values.joined(separator: " / ")
            }
        }
        return elementID
    }
}
