import AppIntents
import Foundation
import UniformTypeIdentifiers
import mp3ChapterReader

struct AddID3TagsIntent: AppIntent {
    static var title: LocalizedStringResource = "Add ID3 Tags"
    static var description = IntentDescription(
        "Adds or updates common ID3 tags on an MP3 file and returns the tagged file.",
        categoryName: "ID3 Tags",
        searchKeywords: ["MP3", "ID3", "metadata", "audio", "tags"]
    )
    static var openAppWhenRun = false

    @Parameter(
        title: "MP3 File",
        description: "The MP3 file to tag.",
        supportedContentTypes: [.mp3]
    )
    var file: IntentFile

    @Parameter(title: "Title")
    var title: String?

    @Parameter(title: "Artist")
    var artist: String?

    @Parameter(title: "Album")
    var album: String?

    @Parameter(title: "Album Artist")
    var albumArtist: String?

    @Parameter(title: "Track Number")
    var trackNumber: String?

    @Parameter(title: "Genre")
    var genre: String?

    @Parameter(title: "Release Date")
    var releaseDate: String?

    @Parameter(title: "Composer")
    var composer: String?

    @Parameter(title: "Podcast URL")
    var podcastURL: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add ID3 tags to \(\.$file)") {
            \.$title
            \.$artist
            \.$album
            \.$albumArtist
            \.$trackNumber
            \.$genre
            \.$releaseDate
            \.$composer
            \.$podcastURL
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let inputData = try await file.data(contentType: .mp3)
        var document = ID3TagDocument(data: inputData)

        apply(title, to: "TIT2", in: &document)
        apply(artist, to: "TPE1", in: &document)
        apply(album, to: "TALB", in: &document)
        apply(albumArtist, to: "TPE2", in: &document)
        apply(trackNumber, to: "TRCK", in: &document)
        apply(genre, to: "TCON", in: &document)
        apply(releaseDate, to: "TDRC", in: &document)
        apply(composer, to: "TCOM", in: &document)

        if let podcastURL = cleaned(podcastURL) {
            document.setURLFrame("WOAF", url: podcastURL)
        }

        let outputData = try document.serializedMP3Data()
        let output = IntentFile(data: outputData, filename: outputFilename, type: UTType(filenameExtension: "mp3") ?? .audio)
        return .result(value: output, dialog: "Added ID3 tags to \(output.filename).")
    }

    private var outputFilename: String {
        let filename = file.filename.isEmpty ? "Tagged.mp3" : file.filename
        if filename.lowercased().hasSuffix(".mp3") {
            return filename
        }
        return "\(filename).mp3"
    }

    private func apply(_ value: String?, to frameID: String, in document: inout ID3TagDocument) {
        guard let value = cleaned(value) else {
            return
        }
        document.setTextFrame(frameID, value: value)
    }

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct IDTagEditorShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddID3TagsIntent(),
            phrases: [
                "Add ID3 tags with \(.applicationName)",
                "Tag MP3 with \(.applicationName)"
            ],
            shortTitle: "Add ID3 Tags",
            systemImageName: "tag"
        )

        AppShortcut(
            intent: IdentifyAndTagID3Intent(),
            phrases: [
                "Identify and tag MP3 with \(.applicationName)",
                "Shazam tag MP3 with \(.applicationName)"
            ],
            shortTitle: "Identify and Tag",
            systemImageName: "waveform.and.magnifyingglass"
        )
    }
}

struct IdentifyAndTagID3Intent: AppIntent {
    static var title: LocalizedStringResource = "Identify and Add ID3 Tags"
    static var description = IntentDescription(
        "Uses ShazamKit to identify an MP3, suggests tag data from the match, applies it, and returns the tagged file.",
        categoryName: "ID3 Tags",
        searchKeywords: ["Shazam", "identify", "MP3", "ID3", "metadata", "song"]
    )
    static var openAppWhenRun = false

    @Parameter(
        title: "MP3 File",
        description: "The MP3 file to identify and tag.",
        supportedContentTypes: [.mp3]
    )
    var file: IntentFile

    @Parameter(title: "Include Artwork", default: true)
    var includeArtwork: Bool

    @Parameter(title: "Include Links", default: true)
    var includeLinks: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Identify and add ID3 tags to \(\.$file)") {
            \.$includeArtwork
            \.$includeLinks
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let inputData = try await file.data(contentType: .mp3)
        let match = try await ShazamID3Identifier.identify(mp3Data: inputData, filename: file.filename)
        var document = ID3TagDocument(data: inputData)
        let artwork = includeArtwork ? await fetchArtwork(for: match) : nil
        ShazamID3Identifier.apply(match, to: &document, includeLinks: includeLinks, artwork: artwork)

        let outputData = try document.serializedMP3Data()
        let output = IntentFile(data: outputData, filename: outputFilename, type: UTType(filenameExtension: "mp3") ?? .audio)
        let dialog = match.dialogTitle.map { "Identified \($0) and added ID3 tags." } ?? "Identified the song and added ID3 tags."
        return .result(value: output, dialog: IntentDialog(stringLiteral: dialog))
    }

    private var outputFilename: String {
        let filename = file.filename.isEmpty ? "Tagged.mp3" : file.filename
        if filename.lowercased().hasSuffix(".mp3") {
            return filename
        }
        return "\(filename).mp3"
    }

    private func fetchArtwork(for match: ShazamID3Identifier.Match) async -> ShazamID3Identifier.Artwork? {
        guard let artworkURL = match.artworkURL else {
            return nil
        }
        return try? await ShazamID3Identifier.fetchArtwork(from: artworkURL)
    }
}
