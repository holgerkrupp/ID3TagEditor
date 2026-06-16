import StoreKit
import SwiftUI

struct SaveUnlockPaywallView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var store: SaveUnlockStore
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "square.and.arrow.down.badge.checkmark")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Unlock Saving")
                        .font(.title2.weight(.semibold))

                    Text("Make a one-time purchase to save edited tags and use Save As. After unlocking, this screen will not appear again.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label("Save edited ID3 tags back to the original file", systemImage: "checkmark.circle")
                Label("Use Save As to write a copy to a new location", systemImage: "checkmark.circle")
                Label("Unlock applies to batch saves too", systemImage: "checkmark.circle")
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.primary)

            if let product = store.product {
                Button {
                    Task {
                        if await store.purchase() {
                            onDismiss()
                        }
                    }
                } label: {
                    if store.isPurchasing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Unlock for \(product.displayPrice)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isPurchasing)
            } else if store.isLoading {
                ProgressView("Loading purchase")
            } else {
                Text("The save unlock purchase is not available.")
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Restore Purchase") {
                    Task {
                        await store.restorePurchases()
                        if store.isUnlocked {
                            onDismiss()
                        }
                    }
                }
                .disabled(store.isPurchasing)

                Spacer()

                Button("Not Now", role: .cancel) {
                    onDismiss()
                }
            }
        }
        .padding(horizontalSizeClass == .compact ? 20 : 28)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        }
        .task {
            await store.configure()
        }
    }
}
