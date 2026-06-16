import SwiftUI

struct TagSummaryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let document: TagDocument
    @Binding var selection: TagSelection?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            SectionPanel("Readable Tags", subtitle: "\(document.topLevelTagFrames.count) top-level tag\(document.topLevelTagFrames.count == 1 ? "" : "s")") {
                if document.topLevelTagFrames.isEmpty {
                    Text("No top-level tag bodies were parsed.")
                        .foregroundStyle(.secondary)
                } else if horizontalSizeClass == .compact {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(document.topLevelTagFrames) { frame in
                            TagBodyCard(frame: frame, editor: document.editorSession, selection: $selection)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                        ForEach(document.topLevelTagFrames) { frame in
                            TagBodyCard(frame: frame, editor: document.editorSession, selection: $selection)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if document.supportsID3ByteInspection {
                ChapterTableView(document: document, selection: $selection)
            }
        }
    }
}
