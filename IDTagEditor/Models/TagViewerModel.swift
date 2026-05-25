import SwiftUI

#if os(macOS)
import AppKit
#endif

@Observable
@MainActor
final class TagViewerModel {
    var documents: [TagDocument] = []
    var selectedID: TagDocument.ID?
    var isImporterPresented = false

    var selectedDocument: TagDocument? {
        guard let selectedID else {
            return documents.first
        }
        return documents.first { $0.id == selectedID }
    }

    func openFileImporter() {
        isImporterPresented = true
    }

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            load(urls)
        case .failure(let error):
            documents.insert(.failed(source: "File import", error: error), at: 0)
            selectedID = documents.first?.id
        }
    }

    func load(_ urls: [URL]) {
        for url in urls {
            load(url)
        }
    }

    func load(_ url: URL) {
        Task {
            let document = await TagDocument.load(from: url)
            documents.insert(document, at: 0)
            selectedID = document.id
        }
    }

    func loadFromPasteboard() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            load(urls)
            return
        }

        if let string = pasteboard.string(forType: .string) {
            let candidates = string
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .compactMap(URL.init(string:))

            if !candidates.isEmpty {
                load(candidates)
                return
            }
        }

        documents.insert(.message(source: "Pasteboard", message: "No MP3 file or URL was found on the pasteboard."), at: 0)
        selectedID = documents.first?.id
        #endif
    }
}
