import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct BatchAlbumEditorView: View {
    @Bindable var batch: BatchAlbumEditor
    let saveAll: () -> Void
    @State private var isArtworkImporterPresented = false
    @State private var patternPreview: [BatchPreviewRow] = []
    @State private var findReplacePreview: [BatchPreviewRow] = []
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            musicBrainzCandidates
            sharedTags
            artworkTools
            applyOptions
            patternTools
            findReplaceTools
            importExportTools
            specializedEditors
            fileManagementTools
            trackList
        }
        .fileImporter(
            isPresented: $isArtworkImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                batch.setArtwork(from: url)
            }
        }
    }

    private var header: some View {
        SectionPanel("Batch Album Tags", subtitle: batch.subtitle) {
            HStack(alignment: .center, spacing: 16) {
                ArtworkView(imageData: batch.artwork?.data, size: 96)
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first else {
                            return false
                        }
                        batch.setArtwork(from: url)
                        return true
                    }
                    .help("Drop cover artwork here")

                VStack(alignment: .leading, spacing: 8) {
                    Text(batch.sourceName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)

                    Text(batch.sourceURL.path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let status = batch.statusMessage, !status.isEmpty {
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(status.contains("\n") ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(batch.selectionSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    batch.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!batch.canUndo)
                .keyboardShortcut("z", modifiers: .command)

                Button {
                    batch.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!batch.canRedo)
                .keyboardShortcut("Z", modifiers: [.command, .shift])

                Button {
                    batch.identifyAll()
                } label: {
                    Label(batch.isIdentifying ? "Identifying" : "Identify Album", systemImage: "waveform.and.magnifyingglass")
                }
                .disabled(batch.isIdentifying || batch.tracks.isEmpty)

                Button {
                    batch.applyToAll()
                } label: {
                    Label("Apply Checked Fields", systemImage: "checkmark.circle")
                }
                .disabled(batch.tracks.isEmpty)

                Button {
                    saveAll()
                } label: {
                    Label(batch.isSaving ? "Saving" : "Save All", systemImage: "square.and.arrow.down")
                }
                .disabled(batch.isSaving || !batch.hasDirtyTracks)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .confirmationDialog(
            "Move selected files to the Trash?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                batch.deleteTargetsFromDisk()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var artworkTools: some View {
        SectionPanel("Artwork Tools", subtitle: "Drop, replace, remove, export, and adjust before embedding") {
            HStack(alignment: .top, spacing: 16) {
                ArtworkView(imageData: batch.artwork?.data, size: 104)
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first else {
                            return false
                        }
                        batch.setArtwork(from: url)
                        return true
                    }
                    .help("Drop artwork here to replace batch artwork")

                VStack(alignment: .leading, spacing: 12) {
                    ArtworkAdjustmentControls(options: batch.artworkOptions)

                    HStack(spacing: 10) {
                        Button {
                            isArtworkImporterPresented = true
                        } label: {
                            Label("Replace Artwork", systemImage: "photo.badge.plus")
                        }

                        Button(role: .destructive) {
                            batch.removeArtwork()
                        } label: {
                            Label("Remove Artwork", systemImage: "trash")
                        }

                        Button {
                            chooseArtworkExportFolder()
                        } label: {
                            Label("Export Embedded Artwork", systemImage: "square.and.arrow.up")
                        }
                    }

                    Text(batch.shouldRemoveArtwork ? "Artwork is marked for removal when checked fields are applied." : "Replacement artwork uses these adjustment settings before it is embedded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var musicBrainzCandidates: some View {
        if !batch.suggestions.isEmpty {
            SectionPanel("MusicBrainz Matches", subtitle: "\(batch.suggestions.count) candidate\(batch.suggestions.count == 1 ? "" : "s")") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(batch.suggestions) { suggestion in
                        MusicBrainzCandidateRow(
                            suggestion: suggestion,
                            isSelected: suggestion.id == batch.selectedSuggestion?.id
                        ) {
                            batch.selectSuggestion(suggestion)
                        }
                    }

                    HStack {
                        Text("Discogs lookup can be added here later for weak MusicBrainz matches or missing artwork.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            batch.applySelectedSuggestion()
                        } label: {
                            Label("Apply Selected Candidate", systemImage: "checkmark.circle")
                        }
                        .disabled(batch.selectedSuggestion == nil)
                    }
                }
            }
        }
    }

    private var sharedTags: some View {
        SectionPanel("Shared Tags", subtitle: "Review before applying") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    field("Album", field: .albumTitle, value: batch.albumTitle)
                    field("Album Artist", field: .albumArtist, value: batch.albumArtist)
                }
                GridRow {
                    field("Artist", field: .artist, value: batch.artist)
                    field("Genre", field: .genre, value: batch.genre)
                }
                GridRow {
                    field("Release Date", field: .releaseDate, value: batch.releaseDate)
                    Text("Use year or full date, for example 2026 or 2026-05-26.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var applyOptions: some View {
        SectionPanel("Apply Only Checked Fields", subtitle: "Unchecked fields are left untouched in every file") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Toggle("Album", isOn: $batch.applyOptions.albumTitle)
                    Toggle("Album Artist", isOn: $batch.applyOptions.albumArtist)
                    Toggle("Artist", isOn: $batch.applyOptions.artist)
                    Toggle("Genre", isOn: $batch.applyOptions.genre)
                }
                GridRow {
                    Toggle("Release Date", isOn: $batch.applyOptions.releaseDate)
                    Toggle("Artwork", isOn: $batch.applyOptions.artwork)
                    Toggle("Titles", isOn: $batch.applyOptions.title)
                    Toggle("Track Numbers", isOn: $batch.applyOptions.trackNumber)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    private var patternTools: some View {
        SectionPanel("Pattern Tools", subtitle: "Rename, extract, and compose with preview") {
            VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Rename files")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("{track}. {title}", text: $batch.renamePattern)
                            .textFieldStyle(.roundedBorder)
                        Button("Preview") {
                            patternPreview = batch.renamePreview()
                        }
                        Button("Apply") {
                            batch.applyRenamePreview()
                            patternPreview = []
                        }
                        .disabled(patternPreview.isEmpty)
                    }

                    GridRow {
                        Text("Extract tags")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("{track} - {title}", text: $batch.filenameExtractPattern)
                            .textFieldStyle(.roundedBorder)
                        Button("Preview") {
                            patternPreview = batch.filenameExtractPreview()
                        }
                        Button("Apply") {
                            batch.applyFilenameExtraction()
                            patternPreview = []
                        }
                    }

                    GridRow {
                        Text("Compose tag")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack {
                            Picker("Field", selection: $batch.composeTargetFrameID) {
                                ForEach(BatchTextField.csvFields) { field in
                                    Text(field.title).tag(field.frameID)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)

                            TextField("{artist} - {title}", text: $batch.composePattern)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button("Preview") {
                            patternPreview = batch.composePreview()
                        }
                        Button("Apply") {
                            batch.applyComposeTags()
                            patternPreview = []
                        }
                    }
                }

                Text("Tokens: {track}, {title}, {album}, {artist}, {albumArtist}, {genre}, {date}, {disc}, {composer}, {sortTitle}, {sortAlbum}, {sortArtist}, {filename}, {ext}")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PreviewTable(rows: patternPreview)
            }
        }
    }

    private var findReplaceTools: some View {
        SectionPanel("Find And Replace", subtitle: "Batch text cleanup with regex and case transforms") {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Find")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Find", text: $batch.findText)
                            .textFieldStyle(.roundedBorder)
                        Text("Replace")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Replace", text: $batch.replaceText)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Toggle("Regex", isOn: $batch.findReplaceUsesRegex)
                            .toggleStyle(.checkbox)
                        Picker("Transform", selection: $batch.textTransform) {
                            ForEach(BatchTextTransform.allCases) { transform in
                                Text(transform.rawValue).tag(transform)
                            }
                        }
                        Button("Preview") {
                            findReplacePreview = batch.findReplacePreview()
                        }
                        Button("Apply") {
                            batch.applyFindReplace()
                            findReplacePreview = []
                        }
                        .disabled(findReplacePreview.isEmpty)
                    }
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(BatchTextField.defaultSearchFields) { field in
                            Toggle(field.title, isOn: Binding(
                                get: { batch.findReplaceFields.contains(field) },
                                set: { isOn in
                                    if isOn {
                                        batch.findReplaceFields.insert(field)
                                    } else {
                                        batch.findReplaceFields.remove(field)
                                    }
                                }
                            ))
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                PreviewTable(rows: findReplacePreview)
            }
        }
    }

    private var importExportTools: some View {
        SectionPanel("Import / Export", subtitle: "CSV, M3U, and copy/paste tags") {
            HStack(spacing: 10) {
                Button {
                    exportCSV()
                } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }

                Button {
                    importCSV()
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }

                Button {
                    exportM3U()
                } label: {
                    Label("Export M3U", systemImage: "music.note.list")
                }

                Button {
                    importM3U()
                } label: {
                    Label("Import M3U", systemImage: "text.badge.plus")
                }

                Divider()
                    .frame(height: 24)

                Button {
                    batch.copyTagsFromFirstTarget()
                } label: {
                    Label("Copy Tags", systemImage: "doc.on.doc")
                }

                Button {
                    batch.pasteCopiedTags()
                } label: {
                    Label("Paste Tags", systemImage: "doc.on.clipboard")
                }
                .disabled(batch.copyTagsBuffer.isEmpty)
            }
        }
    }

    private var specializedEditors: some View {
        SectionPanel("Specialized Tag Editors", subtitle: "Lyrics, comments, dates, BPM, and podcast/audiobook fields") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Episode URL")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("https://example.com/episode", text: $batch.podcastEpisodeURL)
                        .textFieldStyle(.roundedBorder)
                    Text("Release Date")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("2026-05-27", text: $batch.podcastReleaseDate)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Podcast Title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Show or audiobook title", text: $batch.podcastProfileTitle)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        batch.tapTempo()
                    } label: {
                        Label("Tap BPM", systemImage: "metronome")
                    }
                    Button {
                        batch.applySpecializedTags()
                    } label: {
                        Label("Apply Profile", systemImage: "checkmark.circle")
                    }
                }

                GridRow {
                    Text("Description / Comment")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Description", text: $batch.podcastDescription, axis: .vertical)
                        .lineLimit(3...7)
                        .textFieldStyle(.roundedBorder)
                        .gridCellColumns(3)
                }
            }

            Text("Lyrics and comments are editable in the Raw/Summary frame editors; this panel applies shared podcast/audiobook values to the selected files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fileManagementTools: some View {
        SectionPanel("File Management", subtitle: "Finder, directory patterns, batch removal, and Trash") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("{albumArtist}/{album}", text: $batch.directoryPattern)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 260)

                    Button {
                        moveOrCopy(copy: false)
                    } label: {
                        Label("Move To Pattern", systemImage: "folder")
                    }

                    Button {
                        moveOrCopy(copy: true)
                    } label: {
                        Label("Copy To Pattern", systemImage: "folder.badge.plus")
                    }

                    Button {
                        batch.revealTargetsInFinder()
                    } label: {
                        Label("Reveal in Finder", systemImage: "finder")
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        batch.removeTargetsFromBatch()
                    } label: {
                        Label("Remove From Batch", systemImage: "minus.circle")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }

                    Button {
                        refreshMusicApp()
                    } label: {
                        Label("Refresh Music.app", systemImage: "music.note")
                    }
                }
            }
        }
    }

    private var trackList: some View {
        SectionPanel("Tracks", subtitle: "Per-file tags") {
            VStack(spacing: 0) {
                HStack {
                    Button("Select All") {
                        batch.selectAllTracks()
                    }
                    Button("Clear Selection") {
                        batch.clearTrackSelection()
                    }
                    .disabled(batch.selectedTrackIDs.isEmpty)

                    Spacer()

                    Text(batch.selectionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                BatchAlbumTrackHeader()

                Divider()

                ForEach(batch.tracks) { track in
                    BatchAlbumTrackRow(track: track, batch: batch)
                    if track.id != batch.tracks.last?.id {
                        Divider()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.4), lineWidth: 1)
            }
        }
    }

    private func field(_ title: String, field: BatchAlbumSharedField, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if batch.mixedSharedFields.contains(field) {
                    Text(BatchAlbumEditor.multipleValuesPlaceholder)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.13), in: Capsule())
                }
            }
            EditableCommitTextField(title: title, value: value) { newValue in
                batch.updateSharedField(field, value: newValue)
            }
                .frame(minWidth: 220)
        }
    }
}

#if os(macOS)
private extension BatchAlbumEditorView {
    func chooseArtworkExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        if panel.runModal() == .OK, let url = panel.url {
            batch.exportArtwork(to: url)
        }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(batch.sourceName)-tags.csv"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try batch.exportCSV(to: url)
            } catch {
                batch.statusMessage = error.localizedDescription
            }
        }
    }

    func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try batch.importCSV(from: url)
            } catch {
                batch.statusMessage = error.localizedDescription
            }
        }
    }

    func exportM3U() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u") ?? .plainText]
        panel.nameFieldStringValue = "\(batch.sourceName).m3u"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try batch.exportM3U(to: url)
            } catch {
                batch.statusMessage = error.localizedDescription
            }
        }
    }

    func importM3U() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try batch.importM3U(from: url)
            } catch {
                batch.statusMessage = error.localizedDescription
            }
        }
    }

    func moveOrCopy(copy: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = copy ? "Copy" : "Move"
        if panel.runModal() == .OK, let url = panel.url {
            batch.moveOrCopyTargets(to: url, copy: copy)
        }
    }

    func refreshMusicApp() {
        let script = """
        tell application "Music"
            if it is running then
                refresh
            end if
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        batch.statusMessage = error?["NSAppleScriptErrorMessage"] as? String ?? "Asked Music.app to refresh its library view."
    }
}
#else
private extension BatchAlbumEditorView {
    func chooseArtworkExportFolder() {}
    func exportCSV() {}
    func importCSV() {}
    func exportM3U() {}
    func importM3U() {}
    func moveOrCopy(copy: Bool) {}
    func refreshMusicApp() {}
}
#endif

private struct MusicBrainzCandidateRow: View {
    let suggestion: MusicBrainzAlbumSuggestion
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                ArtworkView(imageData: suggestion.artwork?.data, size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(metadata)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(detailMetadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(suggestion.trackCount) tracks")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("Score \(suggestion.score)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isSelected ? Color.accentColor : .secondary.opacity(0.15), in: Capsule())
            }
            .contentShape(Rectangle())
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var metadata: String {
        [suggestion.artist.nilIfEmpty, suggestion.genre.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    private var detailMetadata: String {
        [
            suggestion.country.nilIfEmpty.map { "Country \($0)" },
            suggestion.date.nilIfEmpty.map { "Date \($0)" },
            suggestion.format.nilIfEmpty.map { "Format \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }
}

private struct BatchAlbumTrackHeader: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("")
                Text("#").gridColumnAlignment(.trailing)
                Text("Title")
                Text("File")
                Text("Identification")
                Text("Save")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.35))
    }
}

private struct BatchAlbumTrackRow: View {
    @Bindable var track: BatchAlbumTrack
    @Bindable var batch: BatchAlbumEditor

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Toggle("", isOn: Binding(
                    get: { batch.selectedTrackIDs.contains(track.id) },
                    set: { batch.setTrackSelected(track, isSelected: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)

                EditableCommitTextField(title: "Track", value: track.trackNumber) { value in
                    batch.updateTrackNumber(track, value: value)
                }
                    .frame(width: 64)
                    .gridColumnAlignment(.trailing)

                EditableCommitTextField(title: "Title", value: track.title) { value in
                    batch.updateTrackTitle(track, value: value)
                }
                    .frame(minWidth: 240)

                Text(track.fileURL.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(track.identificationStatus)
                    .font(.callout)
                    .foregroundStyle(track.musicBrainzTrack == nil ? .secondary : .primary)
                    .lineLimit(1)

                Text(track.saveStatus)
                    .font(.callout)
                    .foregroundStyle(track.saveStatus == "Saved" ? .green : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(batch.selectedTrackIDs.contains(track.id) ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}

private struct PreviewTable: View {
    let rows: [BatchPreviewRow]

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(rows.count) previewed change\(rows.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("File")
                        Text("Field")
                        Text("Current")
                        Text("Proposed")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach(rows.prefix(40)) { row in
                        GridRow {
                            Text(row.fileName)
                                .lineLimit(1)
                            Text(row.field)
                                .lineLimit(1)
                            Text(row.current.isEmpty ? "Empty" : row.current)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(row.proposed.isEmpty ? "Empty" : row.proposed)
                                .lineLimit(2)
                        }
                        .font(.caption)
                    }
                }

                if rows.count > 40 {
                    Text("\(rows.count - 40) more change\(rows.count - 40 == 1 ? "" : "s") not shown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
