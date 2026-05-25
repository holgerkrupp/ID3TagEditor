import SwiftUI

struct DocumentHeaderView: View {
    let document: TagDocument

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(document.displayName)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(2)

                Text(document.sourceDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 5) {
                Text(document.header.versionString)
                    .font(.title3.weight(.semibold))

                Text(ByteCountFormatter.id3.string(fromByteCount: Int64(document.header.fileSize)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .glassPanel(cornerRadius: 26)
    }
}
