import SwiftUI

struct AboutCreatedByView: View {
    @Environment(\.openURL) private var openURL

    private let websiteURL = URL(string: "https://extremelysuccessfulapps.com")!
    private let sourceCodeURL = URL(string: "https://github.com/holgerkrupp/IDTagEditor")!

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Text("Created in Buxtehude by")

            linkButton(
                title: "Extremely Successful Apps",
                image: "extremelysuccessfullogo",
                url: websiteURL
            )

            Divider()

            linkButton(
                title: "Get the source code",
                image: "githublogo",
                url: sourceCodeURL
            )

            AboutVersionNumberView()
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func linkButton(title: String, image: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Label(title, image: image)
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

private struct AboutVersionNumberView: View {
    private var versionNumber: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0000"
        return "Version \(version) - (\(build))"
    }

    var body: some View {
        Text(versionNumber)
    }
}

#Preview {
    AboutCreatedByView()
        .padding()
}
