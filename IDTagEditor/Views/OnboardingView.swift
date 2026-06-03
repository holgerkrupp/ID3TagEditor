import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    private let features: [OnboardingFeature] = [
        OnboardingFeature(
            title: "Open Files Quickly",
            description: "Drop MP3 files, choose files or folders, paste copied files, or load file and web URLs from the pasteboard.",
            systemImage: "tray.and.arrow.down"
        ),
        OnboardingFeature(
            title: "Review ID3 Tags",
            description: "Switch between a clean summary, raw frame details, and a hex editor for low-level inspection.",
            systemImage: "text.magnifyingglass"
        ),
        OnboardingFeature(
            title: "Edit and Repair",
            description: "Edit supported tag values, recalculate sizes, rebuild structured tags, and discard hex edits when needed.",
            systemImage: "wrench.and.screwdriver"
        ),
        OnboardingFeature(
            title: "Identify Music",
            description: "Use Shazam for selected tracks or MusicBrainz for album batches to fill in missing metadata.",
            systemImage: "waveform.and.magnifyingglass"
        ),
        OnboardingFeature(
            title: "Batch Albums",
            description: "Select multiple editable files, apply album-level metadata, and save all changed tracks together.",
            systemImage: "rectangle.stack.badge.music.note"
        ),
        OnboardingFeature(
            title: "Artwork and Chapters",
            description: "Inspect embedded artwork, review chapter tables, and keep richer ID3 content visible while editing.",
            systemImage: "photo.on.rectangle.angled"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(features) { feature in
                    OnboardingFeatureCard(feature: feature)
                }
            }

            HStack {
                Text("You can reopen this screen from View > Show Onboarding.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Get Started") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 720)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "tag")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 58, height: 58)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to TagFrame")
                    .font(.largeTitle.weight(.semibold))

                Text("Inspect, identify, edit, repair, and save ID3 metadata for individual MP3 files or full album batches.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
    }
}

private struct OnboardingFeature: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let systemImage: String
}

private struct OnboardingFeatureCard: View {
    let feature: OnboardingFeature

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text(feature.title)
                    .font(.headline)

                Text(feature.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    OnboardingView()
}
