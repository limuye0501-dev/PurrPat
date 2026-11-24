import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Capsule()
                .fill(.primary.opacity(0.2))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
            Text("Purr Pat Pro")
                .font(.largeTitle.weight(.semibold))
            Text("The whole windowsill, once.")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
                feature("paintpalette", "Thirteen coats")
                feature("moon.stars", "Moonlight and rain")
                feature("hand.raised", "Other sleeves")
            }
            .padding(.vertical, 6)
            Button {
                Task { await purchases.purchase() }
            } label: {
                Group {
                    if purchases.isBusy {
                        ProgressView()
                    } else if let price = purchases.displayPrice {
                        Text(String(format: String(localized: "Unlock · %@"), price))
                    } else {
                        Text("Unlock")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(purchases.isBusy)
            Button("Restore purchases") {
                Task { await purchases.restore() }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            Text("One-time purchase. No subscription.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            if let message = purchases.lastMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Color(red: 0.98, green: 0.95, blue: 0.91))
        .onChange(of: purchases.isPro) { _, pro in
            if pro { dismiss() }
        }
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 28)
            Text(title)
                .font(.body)
        }
    }
}
