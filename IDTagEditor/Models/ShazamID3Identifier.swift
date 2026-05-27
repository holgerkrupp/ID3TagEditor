import AVFoundation
import Foundation
import ShazamKit
import mp3ChapterReader

enum ShazamID3Identifier {
    struct Match {
        var title: String?
        var subtitle: String?
        var artist: String?
        var genres: [String]
        var isrc: String?
        var webURL: URL?
        var appleMusicURL: URL?
        var artworkURL: URL?

        nonisolated var dialogTitle: String? {
            guard let title else {
                return nil
            }
            if let artist {
                return "\(title) by \(artist)"
            }
            return title
        }
    }

    struct Artwork {
        var data: Data
        var mimeType: String
    }

    enum Error: LocalizedError {
        case noMatch
        case matchFailed(String)

        var errorDescription: String? {
            switch self {
            case .noMatch:
                "ShazamKit could not identify this MP3."
            case .matchFailed(let message):
                message
            }
        }
    }

    static func identify(mp3Data: Data, filename: String) async throws -> Match {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        try mp3Data.write(to: temporaryURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        let asset = AVURLAsset(url: temporaryURL)
        let signature = try await SHSignatureGenerator.signature(from: asset)
        let session = SHSession()

        if signature.duration <= session.catalog.maximumQuerySignatureDuration {
            return try await match(signature, using: session)
        }

        let duration = min(max(session.catalog.minimumQuerySignatureDuration, 10), session.catalog.maximumQuerySignatureDuration)
        let stride = max(duration / 2, session.catalog.minimumQuerySignatureDuration)
        var attemptedSlices = 0
        var lastError: Swift.Error?

        for try await slice in try signature.slices(from: 0, duration: duration, stride: stride) {
            attemptedSlices += 1
            do {
                return try await match(slice, using: session)
            } catch Error.noMatch {
                if attemptedSlices >= 8 {
                    break
                }
            } catch {
                lastError = error
                if attemptedSlices >= 8 {
                    break
                }
            }
        }

        if let lastError {
            throw lastError
        }
        throw Error.noMatch
    }

    static func fetchArtwork(from url: URL) async throws -> Artwork {
        let (data, response) = try await URLSession.shared.data(from: url)
        let mimeType = (response as? HTTPURLResponse)?.mimeType ?? mimeType(for: url)
        return Artwork(data: data, mimeType: mimeType)
    }

    nonisolated static func apply(_ match: Match, to document: inout ID3TagDocument, includeLinks: Bool, artwork: Artwork?) {
        if let title = match.title {
            document.setTextFrame("TIT2", value: title)
        }
        if let artist = match.artist ?? match.subtitle {
            document.setTextFrame("TPE1", value: artist)
        }
        if !match.genres.isEmpty {
            document.setTextFrame("TCON", value: match.genres.joined(separator: " / "))
        }
        if let isrc = match.isrc {
            document.setTextFrame("TSRC", value: isrc)
        }

        if includeLinks {
            if let appleMusicURL = match.appleMusicURL {
                document.setURLFrame("WXXX", url: appleMusicURL.absoluteString, description: "Apple Music")
            }
            if let webURL = match.webURL {
                document.setURLFrame("WOAF", url: webURL.absoluteString)
            }
        }

        if let artwork {
            document.setPictureFrame(ID3Picture(
                mimeType: artwork.mimeType,
                type: .coverFront,
                description: "Artwork from Shazam",
                data: artwork.data
            ))
        }
    }

    private static func match(_ signature: SHSignature, using session: SHSession) async throws -> Match {
        switch await session.result(from: signature) {
        case .match(let match):
            guard let item = match.mediaItems.first else {
                throw Error.noMatch
            }
            return Match(
                title: cleaned(item.title),
                subtitle: cleaned(item.subtitle),
                artist: cleaned(item.artist),
                genres: item.genres.compactMap(cleaned(_:)),
                isrc: cleaned(item.isrc),
                webURL: item.webURL,
                appleMusicURL: item.appleMusicURL,
                artworkURL: item.artworkURL
            )
        case .noMatch:
            throw Error.noMatch
        case .error(let error, _):
            throw Error.matchFailed(error.localizedDescription)
        }
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func mimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension == "png" {
            return "image/png"
        }
        if pathExtension == "webp" {
            return "image/webp"
        }
        return "image/jpeg"
    }
}
