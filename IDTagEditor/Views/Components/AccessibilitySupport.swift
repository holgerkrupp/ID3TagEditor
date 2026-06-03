import SwiftUI

extension View {
    func controlHelp(_ helpText: String, hint: String? = nil) -> some View {
        self
            .help(helpText)
            .accessibilityHint(Text(hint ?? helpText))
    }

    func selectableElement(
        label: String,
        value: String? = nil,
        hint: String = "Selects this item and highlights its bytes in the inspector.",
        action: @escaping () -> Void
    ) -> some View {
        self
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(value ?? ""))
            .accessibilityHint(Text(hint))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("Select"), action)
    }
}
