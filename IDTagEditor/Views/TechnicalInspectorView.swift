import SwiftUI

struct TechnicalInspectorView: View {
    let document: TagDocument

    var body: some View {
        HeaderSectionView(header: document.header)

        SectionPanel("Frames", subtitle: "\(document.frames.count) frame\(document.frames.count == 1 ? "" : "s")") {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(document.frames) { frame in
                    FrameRowView(frame: frame)
                }
            }
        }
    }
}
