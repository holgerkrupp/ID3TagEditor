import SwiftUI

struct FrameRowView: View {
    let frame: FrameReport
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    InfoRow(label: "Frame ID", value: frame.frameID)
                    InfoRow(label: "Tag name", value: frame.tagName)
                    InfoRow(label: "Original ID", value: frame.originalID)
                    InfoRow(label: "Header size", value: "\(frame.headerSize) bytes")
                    InfoRow(label: "Body size", value: "\(frame.bodySize) bytes")
                    InfoRow(label: "Total size", value: "\(frame.totalSize) bytes")
                    InfoRow(label: "Flags", value: frame.flagsSummary)
                }

                if !frame.details.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(frame.details) { detail in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(detail.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 140, alignment: .leading)

                                Text(detail.value)
                                    .font(.callout)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                if !frame.children.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Embedded frames")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(frame.children) { child in
                            FrameRowView(frame: child)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 12) {
                Text(frame.frameID)
                    .font(.system(.headline, design: .monospaced))
                    .frame(width: 70, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(frame.tagName)
                        .font(.headline)
                    Text(frame.summary)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(frame.bodySize) bytes")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassPanel(cornerRadius: 16)
    }
}
