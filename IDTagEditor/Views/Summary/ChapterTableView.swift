import SwiftUI
import UniformTypeIdentifiers
import mp3ChapterReader

#if os(macOS)
import AppKit
#endif

struct ChapterTableView: View {
    let document: TagDocument
    @Binding var selection: TagSelection?

    @State private var player = WaveformPlaybackModel()
    @State private var isImportPresented = false
    @State private var importResult: ChapterImportResult?
    @State private var importError: String?

    private var chapters: [ChapterReport] {
        document.chapters
    }

    private var editor: EditorSession? {
        document.editorSession
    }

    var body: some View {
        SectionPanel("Chapters", subtitle: "\(chapters.count) chapter\(chapters.count == 1 ? "" : "s")") {
            VStack(alignment: .leading, spacing: 12) {
                if let sourceURL = document.sourceURL {
                    ChapterWaveformView(
                        chapters: chapters,
                        samples: player.samples,
                        duration: player.duration,
                        currentTime: player.currentTime,
                        isEditable: editor?.isEditing == true,
                        selection: $selection,
                        onSeek: player.seek(to:),
                        onMoveChapter: moveChapter(_:to:)
                    )
                    .frame(height: 132)
                    .task(id: sourceURL) {
                        player.load(url: sourceURL)
                    }

                    HStack(spacing: 10) {
                        Button {
                            player.togglePlayback()
                        } label: {
                            Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                        }

                        Text("\(formatTime(player.currentTime)) / \(formatTime(player.duration))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Spacer()

                        if editor?.isEditing == true {
                            Button {
                                isImportPresented = true
                            } label: {
                                Label("Import Chapters", systemImage: "square.and.arrow.down")
                            }
                        }
                    }
                } else if editor?.isEditing == true {
                    Button {
                        isImportPresented = true
                    } label: {
                        Label("Import Chapters", systemImage: "square.and.arrow.down")
                    }
                }

                if chapters.isEmpty {
                    Text("No chapter frames were parsed.")
                        .foregroundStyle(.secondary)
                } else {
                    ChapterGrid(
                        chapters: chapters,
                        editor: editor,
                        selection: $selection
                    )
                }

                if let importError {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .fileImporter(
            isPresented: $isImportPresented,
            allowedContentTypes: [.xml, .plainText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(item: importPreviewBinding) { preview in
            ChapterImportPreview(result: preview.result) { mode in
                applyImport(mode)
            }
        }
    }

    private var importPreviewBinding: Binding<ChapterImportPreviewItem?> {
        Binding {
            importResult.map(ChapterImportPreviewItem.init(result:))
        } set: { value in
            if value == nil {
                importResult = nil
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }

            Task {
                do {
                    let didStartAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if didStartAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    let data = try Data(contentsOf: url)
                    importResult = await ChapterImportParser.shared.parse(data: data, filename: url.lastPathComponent)
                    importError = nil
                } catch {
                    importError = error.localizedDescription
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func applyImport(_ mode: ChapterImportMode) {
        guard let result = importResult, !result.chapters.isEmpty else {
            importResult = nil
            return
        }

        switch mode {
        case .replace:
            editor?.replaceChapters(result.chapters)
        case .merge:
            editor?.mergeChapters(result.chapters)
        }

        importResult = nil
    }

    private func moveChapter(_ chapter: ChapterReport, to seconds: Double) {
        editor?.updateChapter(
            elementID: chapter.elementID,
            startTimeMilliseconds: UInt32(clamping: Int((max(0, seconds) * 1_000).rounded()))
        )
    }
}

private struct ChapterGrid: View {
    var chapters: [ChapterReport]
    var editor: EditorSession?
    @Binding var selection: TagSelection?

    var body: some View {
        VStack(spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Art")
                        .frame(width: 64, alignment: .leading)
                    Text("Chapter")
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: .infinity, alignment: .leading)
                    Text("Time")
                        .frame(width: 132, alignment: .leading)
                    Text("Embedded Content")
                        .frame(minWidth: 280, idealWidth: 420, maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.quaternary.opacity(0.35))

            Divider()

            ForEach(chapters) { chapter in
                let isSelected = selection?.frameSelectionID == chapter.selectionID
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        ChapterArtworkCell(chapter: chapter, editor: editor)
                            .frame(width: 64, alignment: .leading)

                        ChapterTitleCell(chapter: chapter, editor: editor)
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: .infinity, alignment: .leading)

                        ChapterTimeCell(chapter: chapter, editor: editor)
                            .frame(width: 132, alignment: .leading)

                        ChapterContentCell(chapter: chapter, selection: $selection)
                            .frame(minWidth: 280, idealWidth: 420, maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = TagSelection(frameSelectionID: chapter.selectionID, byteRange: chapter.byteRange)
                }

                if chapter.id != chapters.last?.id {
                    Divider()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct ChapterImportPreviewItem: Identifiable {
    let id = UUID()
    var result: ChapterImportResult
}

private enum ChapterImportMode {
    case replace
    case merge
}

private struct ChapterImportPreview: View {
    var result: ChapterImportResult
    var onApply: (ChapterImportMode) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Chapters")
                .font(.title2.weight(.semibold))

            if !result.errors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(result.errors, id: \.self) { error in
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                .font(.callout)
            }

            List(result.chapters, id: \.elementID) { chapter in
                HStack(spacing: 16) {
                    Text(formatTime(Double(chapter.startTimeMilliseconds) / 1_000))
                        .font(.callout.monospacedDigit())
                        .frame(width: 110, alignment: .leading)
                    Text(chapter.displayTitle)
                    Spacer()
                }
            }
            .frame(minHeight: 260)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Merge") {
                    onApply(.merge)
                    dismiss()
                }
                .disabled(result.chapters.isEmpty)
                Button("Replace") {
                    onApply(.replace)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(result.chapters.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
    }
}

private struct ChapterWaveformView: View {
    var chapters: [ChapterReport]
    var samples: [CGFloat]
    var duration: Double
    var currentTime: Double
    var isEditable: Bool
    @Binding var selection: TagSelection?
    var onSeek: (Double) -> Void
    var onMoveChapter: (ChapterReport, Double) -> Void

    @State private var draggedChapterID: ChapterReport.ID?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if isEditable {
                    waveformCanvas
                        .gesture(editDragGesture(width: proxy.size.width))
                } else {
                    waveformCanvas
                        .gesture(tapSeekGesture(width: proxy.size.width))
                }

                ForEach(Array(chapters.enumerated()), id: \.element.elementID) { index, chapter in
                    let isSelected = selection?.frameSelectionID == chapter.selectionID
                    ChapterMarkerView(
                        chapter: chapter,
                        color: chapterColor(for: index, isSelected: isSelected),
                        detailColor: chapterColor(for: index, isSelected: true),
                        isSelected: isSelected,
                        isEditable: isEditable,
                        isDetailPresented: Binding {
                            selection?.frameSelectionID == chapter.selectionID
                        } set: { isPresented in
                            if !isPresented, selection?.frameSelectionID == chapter.selectionID {
                                selection = nil
                            }
                        },
                        onSelect: {
                            selection = TagSelection(frameSelectionID: chapter.selectionID, byteRange: chapter.byteRange)
                        }
                    )
                    .frame(width: 16, height: proxy.size.height)
                    .position(x: xPosition(for: chapter.startTime, width: proxy.size.width), y: proxy.size.height / 2)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var waveformCanvas: some View {
        Canvas { context, size in
            let midY = size.height * 0.52
            let waveformHeight = size.height * 0.68
            let count = max(samples.count, 1)
            let barWidth = max(size.width / CGFloat(count), 1)

            for index in samples.indices {
                let amplitude = max(samples[index], 0.03)
                let x = CGFloat(index) * barWidth
                let height = amplitude * waveformHeight
                let rect = CGRect(x: x, y: midY - height / 2, width: max(barWidth - 0.5, 0.5), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.secondary.opacity(0.45)))
            }

            let playheadX = xPosition(for: currentTime, width: size.width)
            var playhead = Path()
            playhead.move(to: CGPoint(x: playheadX, y: 0))
            playhead.addLine(to: CGPoint(x: playheadX, y: size.height))
            context.stroke(playhead, with: .color(.primary), lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private func tapSeekGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                onSeek(seconds(for: value.location.x, width: width))
            }
    }

    private func editDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) >= abs(value.translation.height) else {
                    return
                }

                let selected = draggedChapterID.flatMap { id in chapters.first { $0.id == id } }
                    ?? nearestChapter(to: value.location.x, width: width)
                draggedChapterID = selected?.id
                if let selected {
                    onMoveChapter(selected, seconds(for: value.location.x, width: width))
                }
            }
            .onEnded { _ in
                draggedChapterID = nil
            }
    }

    private func nearestChapter(to x: CGFloat, width: CGFloat) -> ChapterReport? {
        chapters.min { lhs, rhs in
            abs(xPosition(for: lhs.startTime, width: width) - x) < abs(xPosition(for: rhs.startTime, width: width) - x)
        }
    }

    private func xPosition(for seconds: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else {
            return 0
        }
        return min(max(CGFloat(seconds / duration) * width, 0), width)
    }

    private func seconds(for x: CGFloat, width: CGFloat) -> Double {
        guard width > 0, duration > 0 else {
            return 0
        }
        return min(max(Double(x / width) * duration, 0), duration)
    }

    private func chapterColor(for index: Int, isSelected: Bool) -> Color {
        let hues = [
            0.53,
            0.08,
            0.92,
            0.34,
            0.76,
            0.14,
            0.61,
            0.98
        ]
        return Color(
            hue: hues[index % hues.count],
            saturation: isSelected ? 0.86 : 0.34,
            brightness: isSelected ? 0.94 : 0.72
        )
    }
}

private struct ChapterMarkerView: View {
    var chapter: ChapterReport
    var color: Color
    var detailColor: Color
    var isSelected: Bool
    var isEditable: Bool
    @Binding var isDetailPresented: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .top) {
                Capsule()
                    .fill(color.opacity(isSelected ? 0.95 : 0.74))
                    .frame(width: isSelected ? 4 : 3)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: isSelected ? 12 : 10, height: 20)
                    .shadow(color: color.opacity(0.35), radius: isSelected ? 4 : 2)
            }
            .frame(width: 16)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .popover(isPresented: $isDetailPresented, arrowEdge: .top) {
            ChapterMarkerDetail(chapter: chapter, color: detailColor)
        }
        .accessibilityLabel("Chapter marker \(chapter.title)")
        .accessibilityHint(isEditable ? "Drag horizontally to move, or click for details." : "Click for details.")
    }

    private var helpText: String {
        var lines = [
            chapter.title,
            chapter.timeRange,
            "Duration: \(chapter.duration)"
        ]
        if !chapter.subtitle.isEmpty {
            lines.append(chapter.subtitle)
        }
        if let link = chapter.link {
            lines.append(link)
        }
        return lines.joined(separator: "\n")
    }
}

private struct ChapterMarkerDetail: View {
    var chapter: ChapterReport
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)

                Text(chapter.title)
                    .font(.headline)
                    .lineLimit(3)
            }

            Text(chapter.timeRange)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Text("Duration \(chapter.duration)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if !chapter.subtitle.isEmpty {
                Divider()
                Text(chapter.subtitle)
                    .font(.callout)
                    .lineLimit(4)
            }

            if let link = chapter.link {
                Text(link)
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
}

private struct ChapterTitleCell: View {
    let chapter: ChapterReport
    var editor: EditorSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if editor?.isEditing == true {
                EditableCommitTextField(
                    title: "Chapter title",
                    value: editor?.chapterTitle(elementID: chapter.elementID) ?? chapter.title
                ) { value in
                    editor?.updateChapter(elementID: chapter.elementID, title: value)
                }
            } else {
                Text(chapter.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

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
    var editor: EditorSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if editor?.isEditing == true {
                EditableSecondsField(
                    title: "Start",
                    value: editor?.chapterStartSeconds(elementID: chapter.elementID) ?? chapter.startTime
                ) { value in
                    editor?.updateChapter(elementID: chapter.elementID, startTimeMilliseconds: UInt32(clamping: Int((value * 1_000).rounded())))
                }
            } else {
                Text(chapter.timeRange)
                    .font(.callout.monospacedDigit())
            }
            Text(chapter.duration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct EditableSecondsField: View {
    var title: String
    var value: Double
    var commit: (Double) -> Void

    @State private var draft = ""
    @State private var didInitialize = false
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.roundedBorder)
            .font(.callout.monospacedDigit())
            .focused($isFocused)
            .onAppear {
                if !didInitialize {
                    draft = formatted(value)
                    didInitialize = true
                }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused {
                    draft = formatted(newValue)
                }
            }
            .onChange(of: isFocused) { _, newValue in
                if !newValue {
                    commitIfNeeded()
                }
            }
            .onSubmit(commitIfNeeded)
            .onDisappear(perform: commitIfNeeded)
    }

    private func commitIfNeeded() {
        let normalized = draft.replacingOccurrences(of: ",", with: ".")
        guard let seconds = Double(normalized) else {
            draft = formatted(value)
            return
        }

        guard abs(seconds - value) > 0.0005 else {
            return
        }
        commit(max(0, seconds))
    }

    private func formatted(_ seconds: Double) -> String {
        String(format: "%.3f", seconds)
    }
}

private struct ChapterContentCell: View {
    let chapter: ChapterReport
    @Binding var selection: TagSelection?

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
                let isSelected = selection?.frameSelectionID == frame.selectionID
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
                .padding(.vertical, 3)
                .padding(.horizontal, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = TagSelection(frameSelectionID: frame.selectionID, byteRange: frame.byteRange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct ChapterArtworkCell: View {
    let chapter: ChapterReport
    var editor: EditorSession?

    @State private var artworkOptions = ArtworkAdjustmentOptions()
    @State private var isImporterPresented = false
    @State private var errorMessage: String?

    private var isEditing: Bool {
        editor?.isEditing == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(imageData: chapter.imageData, size: 52)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else {
                        return false
                    }
                    replaceArtwork(from: url)
                    return true
                }
                .help(isEditing ? "Drop artwork for this chapter" : "Chapter artwork")

            if isEditing {
                Menu {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Replace", systemImage: "photo.badge.plus")
                    }

                    Button {
                        exportArtwork()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(chapter.imageData == nil)

                    Divider()

                    ArtworkAdjustmentMenu(options: artworkOptions)

                    Divider()

                    Button(role: .destructive) {
                        editor?.removeChapterArtwork(elementID: chapter.elementID)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .disabled(chapter.imageData == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fileImporter(
                    isPresented: $isImporterPresented,
                    allowedContentTypes: [.image],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        replaceArtwork(from: url)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private func replaceArtwork(from url: URL) {
        guard isEditing else {
            return
        }

        do {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let artwork = try ArtworkProcessor.loadAdjustedArtwork(from: url, options: artworkOptions)
            editor?.setChapterArtwork(elementID: chapter.elementID, artwork: artwork)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportArtwork() {
        #if os(macOS)
        guard let imageData = chapter.imageData else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.nameFieldStringValue = "\(chapter.elementID)-artwork.jpg"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try imageData.write(to: url, options: .atomic)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        #endif
    }
}

private struct ArtworkAdjustmentMenu: View {
    @Bindable var options: ArtworkAdjustmentOptions

    var body: some View {
        Toggle("Square crop", isOn: $options.cropToSquare)
        Picker("Format", selection: $options.outputFormat) {
            ForEach(ArtworkOutputFormat.allCases) { format in
                Text(format.title).tag(format)
            }
        }
        Picker("Max edge", selection: $options.maxPixelSize) {
            Text("600 px").tag(600.0)
            Text("1200 px").tag(1200.0)
            Text("1800 px").tag(1800.0)
            Text("2400 px").tag(2400.0)
        }
        Picker("JPEG quality", selection: $options.jpegQuality) {
            Text("70%").tag(0.70)
            Text("86%").tag(0.86)
            Text("95%").tag(0.95)
            Text("100%").tag(1.0)
        }
        .disabled(options.outputFormat != .jpeg)
    }
}
