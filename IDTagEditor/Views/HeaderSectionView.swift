import SwiftUI

struct HeaderSectionView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let header: ID3HeaderReport

    var body: some View {
        SectionPanel("ID3 Header", subtitle: "10-byte tag header plus computed boundaries") {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows, id: \.label) { row in
                        CompactInfoRow(label: row.label, value: row.value)
                    }
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    ForEach(rows, id: \.label) { row in
                        InfoRow(label: row.label, value: row.value)
                    }
                }
            }
        }
    }

    private var rows: [(label: String, value: String)] {
        [
            ("Identifier", header.identifier),
            ("Version", header.versionString),
            ("Revision", "\(header.revision)"),
            ("Flags byte", header.flagsByteHex),
            ("Unsynchronization", header.hasUnsynchronization.yesNo),
            ("Extended header", header.hasExtendedHeader.yesNo),
            ("Experimental", header.isExperimental.yesNo),
            ("Footer", header.hasFooter.yesNo),
            ("Compressed tag", header.isCompressedTag.yesNo),
            ("Header size", ByteCountFormatter.id3.string(fromByteCount: Int64(header.headerSize))),
            ("Tag body size", "\(header.tagBodySize) bytes"),
            ("Total tag size", "\(header.totalTagSize) bytes"),
            ("Extended header size", "\(header.extendedHeaderSize) bytes"),
            ("Footer size", "\(header.footerSize) bytes"),
            ("Audio starts at", "byte \(header.audioStartOffset)"),
            ("Raw header", header.rawHeaderHex)
        ]
    }
}
