import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

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
        .frame(width: 360)
    }
}

#Preview {
    AboutView()
}
