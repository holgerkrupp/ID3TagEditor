import SwiftUI

struct SidebarView: View {
    @Bindable var model: TagViewerModel

    var body: some View {
        VStack(spacing: 18) {
            DropZoneView()

            List(selection: $model.selectedIDs) {
                ForEach(model.documents) { document in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.displayName)
                            .font(.headline)
                            .lineLimit(1)

                        Text(document.sourceDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(document.id)
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(document.displayName)
                    .accessibilityValue(document.sourceDescription)
                    .accessibilityHint("Selects this file for inspection.")
                }
            }
            .scrollContentBackground(.hidden)
            .accessibilityLabel("Loaded files")
        }
        .padding(18)
    }
}
