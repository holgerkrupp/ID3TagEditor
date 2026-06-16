import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ArtworkView: View {
    let imageData: Data?
    var size: CGFloat = 72
    var accessibilityLabel = "Artwork"

    var body: some View {
        Group {
            #if os(macOS)
            if let imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
            #else
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(imageData == nil ? "No image" : "Image present"))
    }

    private var placeholder: some View {
                Image(systemName: "photo")
                    .font(.system(size: size * 0.35, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.5))
    }
}
