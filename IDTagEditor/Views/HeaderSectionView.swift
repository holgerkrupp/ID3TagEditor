import SwiftUI

struct HeaderSectionView: View {
    let header: ID3HeaderReport

    var body: some View {
        SectionPanel("ID3 Header", subtitle: "10-byte tag header plus computed boundaries") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                InfoRow(label: "Identifier", value: header.identifier)
                InfoRow(label: "Version", value: header.versionString)
                InfoRow(label: "Revision", value: "\(header.revision)")
                InfoRow(label: "Flags byte", value: header.flagsByteHex)
                InfoRow(label: "Unsynchronization", value: header.hasUnsynchronization.yesNo)
                InfoRow(label: "Extended header", value: header.hasExtendedHeader.yesNo)
                InfoRow(label: "Experimental", value: header.isExperimental.yesNo)
                InfoRow(label: "Footer", value: header.hasFooter.yesNo)
                InfoRow(label: "Compressed tag", value: header.isCompressedTag.yesNo)
                InfoRow(label: "Header size", value: ByteCountFormatter.id3.string(fromByteCount: Int64(header.headerSize)))
                InfoRow(label: "Tag body size", value: "\(header.tagBodySize) bytes")
                InfoRow(label: "Total tag size", value: "\(header.totalTagSize) bytes")
                InfoRow(label: "Extended header size", value: "\(header.extendedHeaderSize) bytes")
                InfoRow(label: "Footer size", value: "\(header.footerSize) bytes")
                InfoRow(label: "Audio starts at", value: "byte \(header.audioStartOffset)")
                InfoRow(label: "Raw header", value: header.rawHeaderHex)
            }
        }
    }
}
