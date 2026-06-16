import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            #if os(macOS)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            #else
            Image(systemName: "tag.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 96, height: 96)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
            #endif

            VStack(spacing: 4) {
                Text("TagFrame")
                    .font(.title2.weight(.semibold))

                Text("Inspect and edit ID3 tags.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            AboutCreatedByView()
        }
        .padding(28)
        .frame(maxWidth: 360)
    }
}

#Preview {
    AboutView()
}
