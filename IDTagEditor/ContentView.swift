//
//  ContentView.swift
//  IDTagEditor
//
//  Created by Holger Krupp on 23.05.26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var model = TagViewerModel()
    @State private var isDropTargeted = false
    @State private var isOnboardingPresented = false
    @State private var selectedView = DetailMode.summary
    @State private var tagSelection: TagSelection?

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            detail
        }
        .frame(minWidth: 1080, minHeight: 680)
        .background(appBackground)
        #if os(macOS)
        .background(WindowDocumentEditedObserver(isDocumentEdited: model.hasUnsavedChanges))
        #endif
        .focusedSceneValue(\.tagViewerModel, model)
        .focusedSceneValue(\.detailMode, $selectedView)
        .focusedSceneValue(\.isOnboardingPresented, $isOnboardingPresented)
        .onChange(of: model.selectedIDs) { _, selectedIDs in
            if !selectedIDs.isEmpty {
                model.batchEditor = nil
            }
            tagSelection = nil
        }
        .task {
            if !hasCompletedOnboarding {
                isOnboardingPresented = true
            }
            await model.saveUnlockStore.configure()
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $selectedView) {
                    ForEach(DetailMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.batchEditor != nil)

                if model.batchEditor == nil, model.selectedDocuments.filter(\.canEdit).count > 1 {
                    Button {
                        model.startBatchEditingSelectedDocuments()
                    } label: {
                        Label("Batch Edit", systemImage: "rectangle.stack")
                    }
                }

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

                if let document = model.selectedDocument, document.canEdit {
                    Button {
                        model.identifySelectedDocument()
                    } label: {
                        Label(model.isIdentifyingSelectedDocument ? "Identifying" : "Identify", systemImage: "waveform.and.magnifyingglass")
                    }
                    .disabled(model.isIdentifyingSelectedDocument)

                    Button {
                        model.toggleEditing(for: document)
                    } label: {
                        Label(document.editorSession?.isEditing == true ? "Done" : "Edit", systemImage: document.editorSession?.isEditing == true ? "checkmark.circle" : "pencil")
                    }

                    Button {
                        model.saveActiveItem()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!model.canSaveActiveItem)
                    .keyboardShortcut("s", modifiers: .command)

                    Button {
                        model.saveSelectedDocumentAs()
                    } label: {
                        Label("Save As", systemImage: "square.and.arrow.down.on.square")
                    }
                    .disabled(document.editorSession?.canSave != true)
                }
            }
        }
        .alert("IDTagEditor", isPresented: alertBinding) {
            Button("OK", role: .cancel) {
                model.alertMessage = nil
            }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .sheet(isPresented: savePaywallBinding) {
            SaveUnlockPaywallView(store: model.saveUnlockStore) {
                model.handleSaveUnlockPaywallDismissed()
            }
        }
        .sheet(isPresented: onboardingBinding) {
            OnboardingView()
        }
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: [.mp3, .mpeg4Audio, .audio, .folder],
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
        if let batch = model.batchEditor {
            ScrollView {
                BatchAlbumEditorView(batch: batch) {
                    model.saveBatchAlbum()
                }
                    .padding(24)
            }
            .scrollContentBackground(.hidden)
        } else if let document = model.selectedDocument {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DocumentHeaderView(document: document)

                    switch selectedView {
                    case .summary:
                        TagSummaryView(document: document, selection: $tagSelection)
                    case .raw:
                        TechnicalInspectorView(document: document, selection: $tagSelection)
                    case .hex:
                        HexView(document: document, selection: $tagSelection)
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

    private var alertBinding: Binding<Bool> {
        Binding {
            model.alertMessage != nil
        } set: { isPresented in
            if !isPresented {
                model.alertMessage = nil
            }
        }
    }

    private var savePaywallBinding: Binding<Bool> {
        Binding {
            model.isSavePaywallPresented
        } set: { isPresented in
            if isPresented {
                model.isSavePaywallPresented = true
            } else {
                model.handleSaveUnlockPaywallDismissed()
            }
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding {
            isOnboardingPresented
        } set: { isPresented in
            isOnboardingPresented = isPresented
            if !isPresented {
                hasCompletedOnboarding = true
            }
        }
    }
}

enum DetailMode: String, CaseIterable, Identifiable {
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

#if os(macOS)
private struct WindowDocumentEditedObserver: NSViewRepresentable {
    let isDocumentEdited: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isDocumentEdited = isDocumentEdited
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.isDocumentEdited = isDocumentEdited
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        view.window?.isDocumentEdited = false
    }
}
#endif
