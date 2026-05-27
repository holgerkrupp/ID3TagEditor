import Foundation

struct TagSelection: Equatable {
    var frameSelectionID: String
    var byteRange: Range<Int>?

    var isChapter: Bool {
        frameSelectionID.contains("/CHAP@")
    }
}

struct FrameByteRange {
    var id: String
    var range: Range<Int>
    var childRanges: [FrameByteRange]
}
