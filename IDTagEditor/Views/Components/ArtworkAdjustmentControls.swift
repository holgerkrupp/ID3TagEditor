import SwiftUI

struct ArtworkAdjustmentControls: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var options: ArtworkAdjustmentOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            (horizontalSizeClass == .compact
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 14))) {
                Toggle("Square crop", isOn: $options.cropToSquare)
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif
                    .controlHelp("Crop imported artwork to a square before embedding.")

                Picker("Format", selection: $options.outputFormat) {
                    ForEach(ArtworkOutputFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 170)
                .controlHelp("Choose the file format used when artwork is embedded.")
            }

            (horizontalSizeClass == .compact
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 14))) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max edge \(Int(options.maxPixelSize)) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $options.maxPixelSize, in: 300...2400, step: 100)
                        .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 210)
                        .accessibilityLabel("Maximum artwork edge")
                        .accessibilityValue("\(Int(options.maxPixelSize)) pixels")
                        .controlHelp("Limit embedded artwork to this maximum width or height.")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("JPEG quality \(Int(options.jpegQuality * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $options.jpegQuality, in: 0.45...1.0, step: 0.01)
                        .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 210)
                        .disabled(options.outputFormat != .jpeg)
                        .accessibilityLabel("JPEG quality")
                        .accessibilityValue("\(Int(options.jpegQuality * 100)) percent")
                        .controlHelp("Set JPEG compression quality for embedded artwork.")
                }
            }
        }
    }
}
