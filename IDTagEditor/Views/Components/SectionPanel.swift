import SwiftUI

struct SectionPanel<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            (horizontalSizeClass == .compact
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
                Text(title)
                    .font(.title2.weight(.semibold))

                if horizontalSizeClass != .compact {
                    Spacer()
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(horizontalSizeClass == .compact ? 14 : 18)
        .glassPanel(cornerRadius: 22)
    }
}
