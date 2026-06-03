import Foundation

struct MusicBrainzAlbumSuggestion: Identifiable, Sendable {
    struct Track: Identifiable, Sendable {
        var id: String { "\(position)-\(number)-\(title)" }
        var position: Int
        var number: String
        var title: String
        var artist: String
        var lengthMilliseconds: Int?
    }

    var id: String { releaseID }
    var releaseID: String
    var releaseGroupID: String?
    var title: String
    var artist: String
    var country: String
    var date: String
    var format: String
    var genre: String
    var tracks: [Track]
    var artwork: ShazamID3Identifier.Artwork?
    var score: Int

    var trackCount: Int {
        tracks.count
    }
}

enum MusicBrainzClient {
    enum Error: LocalizedError {
        case noReleaseFound
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noReleaseFound:
                "MusicBrainz could not find a matching album release."
            case .invalidResponse:
                "MusicBrainz returned an unexpected response."
            }
        }
    }

    static func suggestAlbum(
        folderName: String,
        albumTitle: String,
        albumArtist: String,
        artist: String,
        localTracks: [BatchAlbumTrack]
    ) async throws -> MusicBrainzAlbumSuggestion {
        let suggestions = try await suggestAlbums(
            folderName: folderName,
            albumTitle: albumTitle,
            albumArtist: albumArtist,
            artist: artist,
            localTracks: localTracks
        )

        guard let best = suggestions.first else {
            throw Error.noReleaseFound
        }
        return best
    }

    static func suggestAlbums(
        folderName: String,
        albumTitle: String,
        albumArtist: String,
        artist: String,
        localTracks: [BatchAlbumTrack]
    ) async throws -> [MusicBrainzAlbumSuggestion] {
        let query = searchQuery(
            folderName: folderName,
            albumTitle: albumTitle,
            albumArtist: albumArtist,
            artist: artist,
            localTracks: localTracks
        )
        let search = try await searchReleases(query: query)
        let localTitles = localTracks.map(\.title)

        var suggestions: [MusicBrainzAlbumSuggestion] = []
        for release in search.releases.prefix(5) {
            do {
                var suggestion = try await lookupRelease(id: release.id, localTitles: localTitles, localTrackCount: localTracks.count)
                suggestion.artwork = try? await fetchArtwork(releaseID: suggestion.releaseID, releaseGroupID: suggestion.releaseGroupID)
                suggestions.append(suggestion)
            } catch {
                continue
            }
        }

        let sorted = suggestions.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.tracks.count == localTracks.count && rhs.tracks.count != localTracks.count
            }
            return lhs.score > rhs.score
        }

        guard !sorted.isEmpty else {
            throw Error.noReleaseFound
        }
        return sorted
    }

    private static func searchQuery(
        folderName: String,
        albumTitle: String,
        albumArtist: String,
        artist: String,
        localTracks: [BatchAlbumTrack]
    ) -> String {
        let album = cleaned(albumTitle).nilIfEmpty ?? cleaned(folderName)
        let creditedArtist = cleaned(albumArtist).nilIfEmpty ?? cleaned(artist).nilIfEmpty

        var parts = ["release:\"\(album)\""]
        if let creditedArtist {
            parts.append("artist:\"\(creditedArtist)\"")
        }
        if creditedArtist == nil, let firstTitle = localTracks.first?.title.nilIfEmpty {
            parts.append("recording:\"\(firstTitle)\"")
        }
        return parts.joined(separator: " AND ")
    }

    private static func searchReleases(query: String) async throws -> ReleaseSearchResponse {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components.url else {
            throw Error.invalidResponse
        }
        return try await request(url, as: ReleaseSearchResponse.self)
    }

    private static func lookupRelease(id: String, localTitles: [String], localTrackCount: Int) async throws -> MusicBrainzAlbumSuggestion {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "inc", value: "media+recordings+artist-credits+genres+release-groups"),
            URLQueryItem(name: "fmt", value: "json")
        ]
        guard let url = components.url else {
            throw Error.invalidResponse
        }

        let release = try await request(url, as: ReleaseLookupResponse.self)
        let tracks = release.media
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            .flatMap(\.tracks)
            .enumerated()
            .map { index, track in
                MusicBrainzAlbumSuggestion.Track(
                    position: index + 1,
                    number: track.number ?? "\(index + 1)",
                    title: cleaned(track.title.nilIfEmpty ?? track.recording?.title ?? ""),
                    artist: artistCredit(track.artistCredit).nilIfEmpty ?? artistCredit(track.recording?.artistCredit),
                    lengthMilliseconds: track.length ?? track.recording?.length
                )
            }

        return MusicBrainzAlbumSuggestion(
            releaseID: release.id,
            releaseGroupID: release.releaseGroup?.id,
            title: cleaned(release.title),
            artist: artistCredit(release.artistCredit),
            country: cleaned(release.country ?? ""),
            date: cleaned(release.date ?? ""),
            format: releaseFormat(from: release.media),
            genre: primaryGenre(from: release.genres),
            tracks: tracks,
            artwork: nil,
            score: score(tracks: tracks, localTitles: localTitles, localTrackCount: localTrackCount)
        )
    }

    private static func fetchArtwork(releaseID: String, releaseGroupID: String?) async throws -> ShazamID3Identifier.Artwork {
        let releaseURL = URL(string: "https://coverartarchive.org/release/\(releaseID)/front")!
        if let artwork = try? await fetchArtwork(from: releaseURL) {
            return artwork
        }

        if let releaseGroupID {
            let releaseGroupURL = URL(string: "https://coverartarchive.org/release-group/\(releaseGroupID)/front")!
            if let artwork = try? await fetchArtwork(from: releaseGroupURL) {
                return artwork
            }
        }

        throw Error.noReleaseFound
    }

    private static func fetchArtwork(from url: URL) async throws -> ShazamID3Identifier.Artwork {
        let (data, response) = try await URLSession.shared.data(for: artworkRequest(for: url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Error.invalidResponse
        }
        return ShazamID3Identifier.Artwork(data: data, mimeType: http.mimeType ?? mimeType(for: url))
    }

    private static func request<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request(for: url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Error.invalidResponse
        }
        return try JSONDecoder().decode(type, from: data)
    }

    nonisolated private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("TagFrame/1.0 ( https://github.com/holgerkrupp/IDTagEditor )", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    nonisolated private static func artworkRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("TagFrame/1.0 ( https://github.com/holgerkrupp/IDTagEditor )", forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }

    nonisolated private static func score(tracks: [MusicBrainzAlbumSuggestion.Track], localTitles: [String], localTrackCount: Int) -> Int {
        var score = max(0, 100 - abs(tracks.count - localTrackCount) * 18)
        let remoteTitles = tracks.map { normalized($0.title) }
        for localTitle in localTitles.map(normalized(_:)) {
            if remoteTitles.contains(localTitle) {
                score += 16
            } else if remoteTitles.contains(where: { $0.contains(localTitle) || localTitle.contains($0) }) {
                score += 8
            }
        }
        return score
    }

    nonisolated private static func artistCredit(_ credits: [ArtistCredit]?) -> String {
        credits?
            .map { "\($0.name)\($0.joinphrase ?? "")" }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    nonisolated private static func primaryGenre(from genres: [Genre]?) -> String {
        genres?
            .sorted { ($0.count ?? 0) > ($1.count ?? 0) }
            .first?
            .name ?? ""
    }

    nonisolated private static func releaseFormat(from media: [Medium]) -> String {
        let formats = media
            .compactMap { medium -> String? in
                let value = cleaned(medium.format ?? "")
                return value.isEmpty ? nil : value
            }
            .reduce(into: [String]()) { result, format in
                if !result.contains(format) {
                    result.append(format)
                }
            }
        return formats.joined(separator: " + ")
    }

    nonisolated private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    nonisolated private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": "image/png"
        case "webp": "image/webp"
        default: "image/jpeg"
        }
    }
}

private struct ReleaseSearchResponse: Decodable {
    var releases: [ReleaseSearchItem]
}

private struct ReleaseSearchItem: Decodable {
    var id: String
}

private struct ReleaseLookupResponse: Decodable {
    var id: String
    var title: String
    var date: String?
    var country: String?
    var artistCredit: [ArtistCredit]?
    var releaseGroup: ReleaseGroup?
    var media: [Medium]
    var genres: [Genre]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case country
        case artistCredit = "artist-credit"
        case releaseGroup = "release-group"
        case media
        case genres
    }
}

private struct ReleaseGroup: Decodable {
    var id: String
}

private struct Medium: Decodable {
    var position: Int?
    var format: String?
    var tracks: [MusicBrainzTrack]
}

private struct MusicBrainzTrack: Decodable {
    var number: String?
    var title: String
    var length: Int?
    var artistCredit: [ArtistCredit]?
    var recording: Recording?

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case length
        case artistCredit = "artist-credit"
        case recording
    }
}

private struct Recording: Decodable {
    var title: String?
    var length: Int?
    var artistCredit: [ArtistCredit]?

    enum CodingKeys: String, CodingKey {
        case title
        case length
        case artistCredit = "artist-credit"
    }
}

private struct ArtistCredit: Decodable {
    var name: String
    var joinphrase: String?
}

private struct Genre: Decodable {
    var name: String
    var count: Int?
}
