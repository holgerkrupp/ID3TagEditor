import SwiftUI

struct EditableCommitTextField: View {
    var title: String
    var value: String
    var axis: Axis = .horizontal
    var commit: (String) -> Void

    @State private var draft = ""
    @State private var didInitialize = false
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(title, text: $draft, axis: axis)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onAppear {
                if !didInitialize {
                    draft = value
                    didInitialize = true
                }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused {
                    draft = newValue
                }
            }
            .onChange(of: isFocused) { _, newValue in
                if !newValue {
                    commitIfNeeded()
                }
            }
            .onSubmit(commitIfNeeded)
            .onDisappear(perform: commitIfNeeded)
    }

    private func commitIfNeeded() {
        guard draft != value else {
            return
        }
        commit(draft)
    }
}
