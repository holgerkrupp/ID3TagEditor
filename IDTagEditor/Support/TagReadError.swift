import Foundation

enum TagReadError: LocalizedError {
    case noID3Tag

    var errorDescription: String? {
        switch self {
        case .noID3Tag:
            "No supported ID3v2 tag was found."
        }
    }
}
