import SwiftUI

struct FrameRowView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                if horizontalSizeClass == .compact {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(infoRows, id: \.label) { row in
                            CompactInfoRow(label: row.label, value: row.value)
                        }
                    }
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        ForEach(infoRows, id: \.label) { row in
                            InfoRow(label: row.label, value: row.value)
                        }
                    }
                }

                if !frame.details.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(frame.details) { detail in
                            (horizontalSizeClass == .compact
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))) {
                                Text(detail.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: horizontalSizeClass == .compact ? nil : 140, alignment: .leading)

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
            ViewThatFits(in: .horizontal) {
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
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(frame.frameID)
                        .font(.system(.headline, design: .monospaced))
                    Spacer()
                    Text("\(frame.bodySize) bytes")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(frame.tagName)
                    .font(.headline)
                Text(frame.summary)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
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

    private var infoRows: [(label: String, value: String)] {
        [
            ("Frame ID", frame.frameID),
            ("Tag name", frame.tagName),
            ("Original ID", frame.originalID),
            ("Header size", "\(frame.headerSize) bytes"),
            ("Body size", "\(frame.bodySize) bytes"),
            ("Total size", "\(frame.totalSize) bytes"),
            ("Flags", frame.flagsSummary)
        ]
    }
}
