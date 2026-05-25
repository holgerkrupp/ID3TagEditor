import SwiftUI

struct ChapterTableView: View {
    let chapters: [ChapterReport]

    var body: some View {
        SectionPanel("Chapters", subtitle: "\(chapters.count) chapter\(chapters.count == 1 ? "" : "s")") {
            if chapters.isEmpty {
                Text("No chapter frames were parsed.")
                    .foregroundStyle(.secondary)
            } else {
                Table(chapters) {
                    TableColumn("Art") { chapter in
                        ArtworkView(imageData: chapter.imageData, size: 52)
                    }
                    .width(64)

                    TableColumn("Chapter") { chapter in
                        ChapterTitleCell(chapter: chapter)
                    }
                    .width(min: 220, ideal: 280)

                    TableColumn("Time") { chapter in
                        ChapterTimeCell(chapter: chapter)
                    }
                    .width(132)

                    TableColumn("Embedded Content") { chapter in
                        ChapterContentCell(chapter: chapter)
                    }
                    .width(min: 280, ideal: 420)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: tableHeight, idealHeight: tableHeight, maxHeight: tableHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.separator.opacity(0.45), lineWidth: 1)
                }
            }
        }
    }

    private var tableHeight: CGFloat {
        min(max(CGFloat(chapters.count) * 78 + 44, 180), 560)
    }
}

private struct ChapterTitleCell: View {
    let chapter: ChapterReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chapter.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if !chapter.subtitle.isEmpty {
                Text(chapter.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Text(chapter.elementID)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct ChapterTimeCell: View {
    let chapter: ChapterReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chapter.timeRange)
                .font(.callout.monospacedDigit())
            Text(chapter.duration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct ChapterContentCell: View {
    let chapter: ChapterReport

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let link = chapter.link {
                Text(link)
                    .font(.callout)
                    .foregroundStyle(.tint)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            ForEach(chapter.embeddedFrames.filter { $0.frameID != "APIC" }) { frame in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(frame.tagName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)

                    Text(frame.summary)
                        .font(.callout)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
