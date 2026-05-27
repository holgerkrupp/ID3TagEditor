import SwiftUI

struct TagSummaryView: View {
    let document: TagDocument
    @Binding var selection: TagSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionPanel("Readable Tags", subtitle: "\(document.topLevelTagFrames.count) top-level tag\(document.topLevelTagFrames.count == 1 ? "" : "s")") {
                if document.topLevelTagFrames.isEmpty {
                    Text("No top-level tag bodies were parsed.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(document.topLevelTagFrames) { frame in
                            TagBodyCard(frame: frame, editor: document.editorSession, selection: $selection)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ChapterTableView(document: document, selection: $selection)
        }
    }
}
