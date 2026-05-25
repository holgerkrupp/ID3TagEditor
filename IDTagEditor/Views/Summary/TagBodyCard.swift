import SwiftUI

struct TagBodyCard: View {
    let frame: FrameReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if frame.imageData != nil {
                    ArtworkView(imageData: frame.imageData, size: 92)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(frame.tagName)
                            .font(.headline)
                            .lineLimit(2)

                        Text(frame.frameID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }

                    Text("\(frame.bodySize) bytes")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if !frame.summary.isEmpty {
                Text(frame.summary)
                    .font(.callout)
                    .textSelection(.enabled)
                    .lineLimit(frame.imageData == nil ? 5 : 3)
            }

            if !frame.details.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(frame.details) { detail in
                        if detail.label != "Values" || detail.value != frame.summary {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(detail.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text(detail.value)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .lineLimit(6)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .glassPanel(cornerRadius: 16)
    }
}
