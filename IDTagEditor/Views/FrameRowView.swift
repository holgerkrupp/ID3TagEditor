import SwiftUI

struct FrameRowView: View {
    let frame: FrameReport
    var editor: EditorSession?
    @Binding var selection: TagSelection?
    @State private var isExpanded = false

    private var isSelected: Bool {
        selection?.frameSelectionID == frame.selectionID
    }

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

                                if editor?.isEditing == true, (detail.label == "Values" || detail.label == "Value"), editor?.mediaKind == .mp4 || frame.frameID.hasPrefix("T") {
                                    EditableCommitTextField(
                                        title: detail.label,
                                        value: editor?.textValue(for: frame.frameID) ?? detail.value,
                                        axis: .vertical
                                    ) { value in
                                        editor?.setTextFrame(frame.frameID, value: value)
                                    }
                                } else if editor?.isEditing == true, detail.label == "URL", frame.frameID.hasPrefix("W") {
                                    EditableCommitTextField(
                                        title: detail.label,
                                        value: editor?.urlValue(for: frame.frameID) ?? detail.value
                                    ) { value in
                                        editor?.setURLFrame(frame.frameID, url: value)
                                    }
                                } else {
                                    Text(detail.value)
                                        .font(.callout)
                                        .textSelection(.enabled)
                                }
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
                            FrameRowView(frame: child, editor: editor, selection: $selection)
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
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.72), lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            selection = TagSelection(frameSelectionID: frame.selectionID, byteRange: frame.byteRange)
        }
        .selectableElement(
            label: "\(frame.tagName), \(frame.frameID)",
            value: "\(frame.summary), \(frame.bodySize) bytes",
            hint: "Selects this frame, expands details with the disclosure control, and highlights its bytes in the hex view."
        ) {
            selection = TagSelection(frameSelectionID: frame.selectionID, byteRange: frame.byteRange)
        }
    }
}
