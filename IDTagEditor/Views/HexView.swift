import SwiftUI

#if os(macOS)
import AppKit
#endif

struct HexView: View {
    let document: TagDocument

    var body: some View {
        SectionPanel("Hex View", subtitle: "\(document.rawTagData.count) ID3 tag bytes") {
            if document.rawTagData.isEmpty {
                Text("No tag bytes are available.")
                    .foregroundStyle(.secondary)
            } else {
                HexEditorRepresentable(data: document.rawTagData)
                    .frame(minHeight: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.separator.opacity(0.45), lineWidth: 1)
                    }
            }
        }
    }
}

#if os(macOS)
private struct HexEditorRepresentable: NSViewRepresentable {
    var data: Data

    func makeNSView(context: Context) -> NSScrollView {
        let editorView = HexEditorCanvas()
        editorView.data = data

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = editorView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let editorView = scrollView.documentView as? HexEditorCanvas else {
            return
        }

        editorView.data = data
    }
}

private final class HexEditorCanvas: NSView {
    private enum Section {
        case hex
        case ascii
    }

    private enum Metrics {
        static let bytesPerRow = 16
        static let rowHeight: CGFloat = 22
        static let topInset: CGFloat = 12
        static let bottomInset: CGFloat = 12
        static let leftInset: CGFloat = 14
        static let offsetWidth: CGFloat = 92
        static let byteCellWidth: CGFloat = 28
        static let byteGroupGap: CGFloat = 12
        static let asciiGap: CGFloat = 22
        static let asciiCellWidth: CGFloat = 11
        static let highlightCornerRadius: CGFloat = 4

        static var hexStartX: CGFloat {
            leftInset + offsetWidth
        }

        static var asciiStartX: CGFloat {
            hexStartX + byteCellWidth * CGFloat(bytesPerRow) + byteGroupGap + asciiGap
        }

        static var contentWidth: CGFloat {
            asciiStartX + asciiCellWidth * CGFloat(bytesPerRow) + leftInset
        }
    }

    var data = Data() {
        didSet {
            guard data != oldValue else {
                return
            }
            selectedByteRange = nil
            anchorByteIndex = nil
            activeSection = nil
            updateFrameSize()
            needsDisplay = true
        }
    }

    private var selectedByteRange: Range<Int>?
    private var anchorByteIndex: Int?
    private var activeSection: Section?
    private let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private let secondaryFont = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

    private lazy var textAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.labelColor
    ]

    private lazy var offsetAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.secondaryLabelColor
    ]

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        postsFrameChangedNotifications = true
        updateFrameSize()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        postsFrameChangedNotifications = true
        updateFrameSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateFrameSize()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        dirtyRect.fill()

        let firstRow = max(0, Int(floor((dirtyRect.minY - Metrics.topInset) / Metrics.rowHeight)))
        let lastRow = min(rowCount - 1, Int(ceil((dirtyRect.maxY - Metrics.topInset) / Metrics.rowHeight)))
        guard firstRow <= lastRow else {
            return
        }

        for row in firstRow...lastRow {
            drawRow(row)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)
        guard let hit = hitTestByte(at: point) else {
            selectedByteRange = nil
            anchorByteIndex = nil
            activeSection = nil
            needsDisplay = true
            return
        }

        anchorByteIndex = hit.byteIndex
        activeSection = hit.section
        selectedByteRange = hit.byteIndex..<(hit.byteIndex + 1)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchorByteIndex else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let byteIndex = clampedByteIndex(at: point, preferredSection: activeSection)
        let lower = min(anchorByteIndex, byteIndex)
        let upper = max(anchorByteIndex, byteIndex) + 1
        selectedByteRange = lower..<upper
        autoscroll(with: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard anchorByteIndex != nil else {
            return
        }

        mouseDragged(with: event)
    }

    @objc func copy(_ sender: Any?) {
        guard let selectedByteRange else {
            NSSound.beep()
            return
        }

        let bytes = Array(data[selectedByteRange])
        let string = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
            copy(nil)
            return
        }

        super.keyDown(with: event)
    }

    private func updateFrameSize() {
        let height = Metrics.topInset + Metrics.bottomInset + CGFloat(rowCount) * Metrics.rowHeight
        frame.size = NSSize(width: Metrics.contentWidth, height: max(height, 1))
        invalidateIntrinsicContentSize()
    }

    private func drawRow(_ row: Int) {
        let rowByteStart = row * Metrics.bytesPerRow
        let y = Metrics.topInset + CGFloat(row) * Metrics.rowHeight

        drawOffset(rowByteStart, y: y)

        for column in 0..<Metrics.bytesPerRow {
            let byteIndex = rowByteStart + column
            guard byteIndex < data.count else {
                continue
            }

            let byte = data[byteIndex]
            drawCellHighlight(byteIndex: byteIndex, section: .hex)
            drawCellHighlight(byteIndex: byteIndex, section: .ascii)

            String(format: "%02X", byte).draw(at: NSPoint(x: hexCellRect(row: row, column: column).minX + 3, y: y + 2), withAttributes: textAttributes)
            printableCharacter(for: byte).draw(at: NSPoint(x: asciiCellRect(row: row, column: column).minX + 1, y: y + 2), withAttributes: textAttributes)
        }
    }

    private func drawOffset(_ offset: Int, y: CGFloat) {
        String(format: "%08X", offset).draw(at: NSPoint(x: Metrics.leftInset, y: y + 2), withAttributes: offsetAttributes)
    }

    private func drawCellHighlight(byteIndex: Int, section: Section) {
        guard let selectedByteRange, selectedByteRange.contains(byteIndex) else {
            return
        }

        let row = byteIndex / Metrics.bytesPerRow
        let column = byteIndex % Metrics.bytesPerRow
        let rect = section == .hex ? hexCellRect(row: row, column: column) : asciiCellRect(row: row, column: column)
        let color = section == activeSection
            ? NSColor.systemYellow.withAlphaComponent(0.34)
            : NSColor.systemTeal.withAlphaComponent(0.34)

        color.setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 2), xRadius: Metrics.highlightCornerRadius, yRadius: Metrics.highlightCornerRadius).fill()
    }

    private func hitTestByte(at point: NSPoint) -> (byteIndex: Int, section: Section)? {
        let row = Int(floor((point.y - Metrics.topInset) / Metrics.rowHeight))
        guard row >= 0, row < rowCount else {
            return nil
        }

        if let column = hexColumn(atX: point.x) {
            let byteIndex = row * Metrics.bytesPerRow + column
            guard byteIndex < data.count else {
                return nil
            }
            return (byteIndex, .hex)
        }

        if let column = asciiColumn(atX: point.x) {
            let byteIndex = row * Metrics.bytesPerRow + column
            guard byteIndex < data.count else {
                return nil
            }
            return (byteIndex, .ascii)
        }

        return nil
    }

    private func clampedByteIndex(at point: NSPoint, preferredSection: Section?) -> Int {
        guard !data.isEmpty else {
            return 0
        }

        let row = min(max(0, Int(floor((point.y - Metrics.topInset) / Metrics.rowHeight))), rowCount - 1)
        let section = preferredSection ?? .hex
        let column: Int

        switch section {
        case .hex:
            column = clampedHexColumn(atX: point.x)
        case .ascii:
            column = clampedAsciiColumn(atX: point.x)
        }

        return min(row * Metrics.bytesPerRow + column, data.count - 1)
    }

    private func hexColumn(atX x: CGFloat) -> Int? {
        let normalized = x - Metrics.hexStartX
        guard normalized >= 0 else {
            return nil
        }

        let totalWidth = Metrics.byteCellWidth * CGFloat(Metrics.bytesPerRow) + Metrics.byteGroupGap
        guard normalized < totalWidth else {
            return nil
        }

        if normalized >= Metrics.byteCellWidth * 8, normalized < Metrics.byteCellWidth * 8 + Metrics.byteGroupGap {
            return nil
        }

        return clampedHexColumn(atX: x)
    }

    private func clampedHexColumn(atX x: CGFloat) -> Int {
        var normalized = x - Metrics.hexStartX
        if normalized >= Metrics.byteCellWidth * 8 + Metrics.byteGroupGap {
            normalized -= Metrics.byteGroupGap
        }
        return min(max(0, Int(floor(normalized / Metrics.byteCellWidth))), Metrics.bytesPerRow - 1)
    }

    private func asciiColumn(atX x: CGFloat) -> Int? {
        let normalized = x - Metrics.asciiStartX
        guard normalized >= 0, normalized < Metrics.asciiCellWidth * CGFloat(Metrics.bytesPerRow) else {
            return nil
        }

        return clampedAsciiColumn(atX: x)
    }

    private func clampedAsciiColumn(atX x: CGFloat) -> Int {
        let normalized = x - Metrics.asciiStartX
        return min(max(0, Int(floor(normalized / Metrics.asciiCellWidth))), Metrics.bytesPerRow - 1)
    }

    private func hexCellRect(row: Int, column: Int) -> NSRect {
        let groupOffset = column >= 8 ? Metrics.byteGroupGap : 0
        return NSRect(
            x: Metrics.hexStartX + CGFloat(column) * Metrics.byteCellWidth + groupOffset,
            y: Metrics.topInset + CGFloat(row) * Metrics.rowHeight,
            width: Metrics.byteCellWidth,
            height: Metrics.rowHeight
        )
    }

    private func asciiCellRect(row: Int, column: Int) -> NSRect {
        NSRect(
            x: Metrics.asciiStartX + CGFloat(column) * Metrics.asciiCellWidth,
            y: Metrics.topInset + CGFloat(row) * Metrics.rowHeight,
            width: Metrics.asciiCellWidth,
            height: Metrics.rowHeight
        )
    }

    private var rowCount: Int {
        max(1, Int(ceil(Double(data.count) / Double(Metrics.bytesPerRow))))
    }

    private func printableCharacter(for byte: UInt8) -> String {
        switch byte {
        case 0x20...0x7E:
            String(Character(UnicodeScalar(byte)))
        default:
            "."
        }
    }
}
#endif
