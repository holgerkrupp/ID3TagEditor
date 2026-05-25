import SwiftUI

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.callout.monospacedDigit())
                .textSelection(.enabled)
        }
    }
}
