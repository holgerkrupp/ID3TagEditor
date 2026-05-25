//
//  ContentView.swift
//  IDTagEditor
//
//  Created by Holger Krupp on 23.05.26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = TagViewerModel()
    @State private var isDropTargeted = false
    @State private var selectedView = DetailMode.summary

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            detail
        }
        .frame(minWidth: 1080, minHeight: 680)
        .background(appBackground)
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $selectedView) {
                    ForEach(DetailMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    model.openFileImporter()
                } label: {
                    Label("Open", systemImage: "folder")
                }

                Button {
                    model.loadFromPasteboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: .command)
            }
        }
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: [.mp3, .mpeg4Audio, .audio],
            allowsMultipleSelection: true
        ) { result in
            model.handleImport(result)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.load(urls)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, dash: [9, 8]))
                    .padding(18)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let document = model.selectedDocument {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DocumentHeaderView(document: document)

                    switch selectedView {
                    case .summary:
                        TagSummaryView(document: document)
                    case .raw:
                        TechnicalInspectorView(document: document)
                    case .hex:
                        HexView(document: document)
                    }
                }
                .padding(24)
            }
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView {
                Label("No MP3 Loaded", systemImage: "music.note")
            } description: {
                Text("Open, drop, or paste an MP3 file or URL to inspect its ID3v2 tags.")
            } actions: {
                Button("Open MP3") {
                    model.openFileImporter()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .controlBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private enum DetailMode: String, CaseIterable, Identifiable {
    case summary
    case raw
    case hex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: "Summary"
        case .raw: "Raw"
        case .hex: "Hex"
        }
    }

    var systemImage: String {
        switch self {
        case .summary: "text.badge.checkmark"
        case .raw: "tag"
        case .hex: "number"
        }
    }
}

#Preview {
    ContentView()
}
