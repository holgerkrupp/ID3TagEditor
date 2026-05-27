import SwiftUI

struct IDTagEditorCommands: Commands {
    @FocusedValue(\.tagViewerModel) private var model
    @FocusedValue(\.detailMode) private var detailMode
    @FocusedValue(\.isOnboardingPresented) private var isOnboardingPresented

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open File or Folder...") {
                model?.openFileImporter()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open from Pasteboard") {
                model?.loadFromPasteboard()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                model?.saveActiveItem()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(model?.canSaveActiveItem != true)

            Button("Save As...") {
                model?.saveSelectedDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(model?.canSaveSelectedDocumentAs != true)

            if model?.shouldShowSaveUnlock == true {
                Divider()

                Button("Unlock Saving...") {
                    model?.showSaveUnlock()
                }
            }
        }

        CommandGroup(after: .toolbar) {
            Divider()

            Button("Show Onboarding") {
                isOnboardingPresented?.wrappedValue = true
            }
            .disabled(isOnboardingPresented == nil)

            Divider()

            Button("Show Summary") {
                detailMode?.wrappedValue = .summary
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(detailMode == nil || model?.batchEditor != nil)

            Button("Show Raw Tags") {
                detailMode?.wrappedValue = .raw
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(detailMode == nil || model?.batchEditor != nil)

            Button("Show Hex Editor") {
                detailMode?.wrappedValue = .hex
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(detailMode == nil || model?.batchEditor != nil)
        }

        CommandMenu("Tag") {
            Button(model?.selectedDocumentIsEditing == true ? "End Editing" : "Edit Tag") {
                if let document = model?.selectedDocument {
                    model?.toggleEditing(for: document)
                }
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(model?.canToggleSelectedDocumentEditing != true)

            Divider()

            Button("Identify Selected File with Shazam") {
                model?.identifySelectedDocument()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(model?.canIdentifySelectedDocument != true)

            Button("Identify Album with MusicBrainz") {
                model?.identifyBatchAlbum()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(model?.canRunBatchActions != true || model?.batchEditor?.isIdentifying == true)

            Divider()

            Button("Apply Batch Album Tags") {
                model?.applyBatchTags()
            }
            .disabled(model?.canRunBatchActions != true)

            Button("Save All Batch Changes") {
                model?.saveBatchAlbum()
            }
            .disabled(model?.batchEditor?.hasDirtyTracks != true || model?.batchEditor?.isSaving == true)

            Divider()

            Menu("Repair Tag") {
                Button("Recalculate Sizes") {
                    model?.recalculateSelectedTagSizes()
                }
                .disabled(model?.selectedDocument?.editorSession == nil)

                Button("Rebuild from Structured Tags") {
                    model?.rebuildSelectedTagFromStructuredTags()
                }
                .disabled(model?.selectedDocument?.editorSession == nil)

                Button("Discard Hex Edits") {
                    model?.discardSelectedHexEdits()
                }
                .disabled(model?.selectedDocument?.editorSession == nil)
            }
        }
    }
}

private struct TagViewerModelFocusedKey: FocusedValueKey {
    typealias Value = TagViewerModel
}

private struct DetailModeFocusedKey: FocusedValueKey {
    typealias Value = Binding<DetailMode>
}

private struct OnboardingPresentationFocusedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var tagViewerModel: TagViewerModel? {
        get { self[TagViewerModelFocusedKey.self] }
        set { self[TagViewerModelFocusedKey.self] = newValue }
    }

    var detailMode: Binding<DetailMode>? {
        get { self[DetailModeFocusedKey.self] }
        set { self[DetailModeFocusedKey.self] = newValue }
    }

    var isOnboardingPresented: Binding<Bool>? {
        get { self[OnboardingPresentationFocusedKey.self] }
        set { self[OnboardingPresentationFocusedKey.self] = newValue }
    }
}
