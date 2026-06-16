//
//  ContentView.swift
//  IDTagEditor
//
//  Created by Holger Krupp on 23.05.26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var model = TagViewerModel()
    @State private var isDropTargeted = false
    @State private var isOnboardingPresented = false
    @State private var selectedView = DetailMode.summary
    @State private var tagSelection: TagSelection?
    @State private var preferredCompactColumn = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            detail
        }
        .platformWindowSizing()
       
        .trackMacDocumentEdited(model.hasUnsavedChanges)
        .focusedSceneValue(\.tagViewerModel, model)
        .focusedSceneValue(\.detailMode, $selectedView)
        .focusedSceneValue(\.isOnboardingPresented, $isOnboardingPresented)
        .onChange(of: model.selectedIDs) { _, selectedIDs in
            if !selectedIDs.isEmpty {
                model.batchEditor = nil
                preferredCompactColumn = .detail
            }
            tagSelection = nil
        }
        .onChange(of: model.batchEditor != nil) { _, isBatchEditing in
            if isBatchEditing {
                preferredCompactColumn = .detail
            }
        }
        .task {
            if !hasCompletedOnboarding {
                isOnboardingPresented = true
            }
            await model.restoreRecentlyOpenedFiles()
            await model.saveUnlockStore.configure()
        }
        .alert("TagFrame", isPresented: alertBinding) {
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
        .onOpenURL { url in
            model.load(url)
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
        Group {
            if let batch = model.batchEditor {
                ScrollView {
                    BatchAlbumEditorView(batch: batch) {
                        model.saveBatchAlbum()
                    }
                    .padding(contentPadding)
                }
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Batch album editor")
            } else if let document = model.selectedDocument {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DocumentHeaderView(
                            document: document,
                            isIdentifyingWithShazam: model.isIdentifyingSelectedDocument
                        )
                        
                        switch selectedView {
                        case .summary:
                            TagSummaryView(document: document, selection: $tagSelection)
                        case .raw:
                            if document.supportsID3ByteInspection {
                                TechnicalInspectorView(document: document, selection: $tagSelection)
                            } else {
                                ContentUnavailableView("Raw ID3 View Unavailable", systemImage: "tag", description: Text("This file uses MPEG-4 metadata, which does not expose ID3 tag bytes."))
                            }
                        case .hex:
                            if document.supportsID3ByteInspection {
                                HexView(document: document, selection: $tagSelection)
                            } else {
                                ContentUnavailableView("Hex View Unavailable", systemImage: "number", description: Text("MPEG-4/AAC metadata is not exposed as ID3 tag bytes."))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(contentPadding)
                }
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Tag inspector for \(document.displayName)")
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
        .toolbar {
            if model.selectedDocument != nil {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $selectedView) {
                        ForEach(DetailMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.batchEditor != nil)
                    .controlHelp("Switch between summary, raw tag, and hex views.", hint: "Choose which inspector view is shown.")
                    .accessibilityLabel("Inspector view")
                }
            }


            ToolbarItemGroup(placement: .primaryAction) {
                // Batch Edit Switcher Button (visible when multi-selection exists, but batching hasn't started)
                if model.batchEditor == nil, model.selectedDocuments.filter(\.canEdit).count > 1 {
                    Button {
                        model.startBatchEditingSelectedDocuments()
                    } label: {
                        Label("Batch Edit", systemImage: "rectangle.stack")
                    }
                    .controlHelp("Batch edit the selected editable files.")
                }
                
                // Individual Edit/Done Button (hidden when multi-batch editing is live)
                if model.batchEditor == nil, let document = model.selectedDocument, document.canEdit {
                    Button {
                        model.toggleEditing(for: document)
                    } label: {
                        Label(
                            document.editorSession?.isEditing == true ? "Done" : "Edit",
                            systemImage: document.editorSession?.isEditing == true ? "checkmark" : "pencil"
                        )
                    }
                    .controlHelp(document.editorSession?.isEditing == true ? "Finish editing this tag." : "Edit the selected tag fields.")
                }

                // Global Cross-Platform Contextual Actions Menu
                Menu {
                    Section {
                        Button {
                            model.openFileImporter()
                        } label: {
                            Label("Open", systemImage: "folder")
                        }
                        .controlHelp("Open MP3 files, audio files, or folders.")

                        Button {
                            model.loadFromPasteboard()
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                        .keyboardShortcut("v", modifiers: .command)
                        .controlHelp("Load copied files, file URLs, or web URLs from the pasteboard.")
                    }

                    Section {
                        Button {
                            if model.batchEditor != nil {
                                model.saveBatchAlbum()
                            } else {
                                model.saveActiveItem()
                            }
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .disabled((model.batchEditor == nil && !model.canSaveActiveItem))
                        .keyboardShortcut("s", modifiers: .command)
                        .controlHelp("Save changes to the active file or batch.")

                        if model.batchEditor == nil, let document = model.selectedDocument {
                            Button {
                                model.saveSelectedDocumentAs()
                            } label: {
                                Label("Save As...", systemImage: "square.and.arrow.down.on.square")
                            }
                            .disabled(document.editorSession?.canSave != true)
                            .controlHelp("Save a copy of the selected file with edited tags.")
                        }

                        Button(role: .destructive) {
                            if model.batchEditor != nil {
                                model.batchEditor = nil
                            } else {
                                model.discardActiveEdits()
                            }
                        } label: {
                            Label(model.batchEditor != nil ? "Cancel Batch" : "Dismiss Edits", systemImage: "xmark.circle")
                        }
                        .disabled(model.batchEditor == nil && !model.canDiscardActiveEdits)
                        .controlHelp(model.batchEditor != nil ? "Cancel batch editing operations." : "Discard unsaved manual and identified tag edits.")
                    }

                    if model.batchEditor == nil, model.selectedDocument != nil {
                        Section {
                            Button {
                                model.identifySelectedDocument()
                            } label: {
                                Label(model.isIdentifyingSelectedDocument ? "Identifying..." : "Identify with Shazam", systemImage: "waveform.and.magnifyingglass")
                            }
                            .disabled(model.isIdentifyingSelectedDocument)
                            .controlHelp("Identify the selected file with Shazam metadata lookup.")
                        }
                    }

                    Section {
                        Button {
                            isOnboardingPresented = true
                        } label: {
                            Label("Help", systemImage: "questionmark.circle")
                        }
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
    }





    private var contentPadding: CGFloat {
        horizontalSizeClass == .compact ? 12 : 24
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

// Private extensions containing the platform-specific logic wrappers.
// Keeps the main View completely clean of inline #if blocks.
private extension View {
    @ViewBuilder
    func platformWindowSizing() -> some View {
        #if os(macOS)
        frame(minWidth: 1080, minHeight: 680)
        #else
        self
        #endif
    }
    
    @ViewBuilder
    func trackMacDocumentEdited(_ isEdited: Bool) -> some View {
        #if os(macOS)
        self.background(WindowDocumentEditedObserver(isDocumentEdited: isEdited))
        #else
        self
        #endif
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
