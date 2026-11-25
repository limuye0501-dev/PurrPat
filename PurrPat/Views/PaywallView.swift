import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 0.29, green: 0.18, blue: 0.12)
    private let inkSoft = Color(red: 0.45, green: 0.32, blue: 0.22)
    private let paper = Color(red: 0.98, green: 0.95, blue: 0.91)
    private let button = Color(red: 0.42, green: 0.28, blue: 0.18)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Capsule()
                .fill(ink.opacity(0.25))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
            Text("Purr Pat Pro")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(ink)
            Text("The whole windowsill, once.")
                .font(.title3)
                .foregroundStyle(inkSoft)
            VStack(alignment: .leading, spacing: 16) {
                feature("paintpalette", "Seven more coats")
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
                            .tint(.white)
                    } else if let price = purchases.displayPrice {
                        Text(String(format: String(localized: "Unlock · %@"), price))
                    } else {
                        Text("Unlock")
                    }
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(button)
            .disabled(purchases.isBusy)
            .accessibilityIdentifier("unlock-pro")
            Button("Restore purchases") {
                Task { await purchases.restore() }
            }
            .font(.subheadline)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            Text("One-time purchase. No subscription.")
                .font(.footnote)
                .foregroundStyle(inkSoft)
                .frame(maxWidth: .infinity)
            if let message = purchases.lastMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(inkSoft)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(paper)
        .preferredColorScheme(.light)
        .onChange(of: purchases.isPro) { _, pro in
            if pro { dismiss() }
        }
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(ink)
                .frame(width: 28)
            Text(title)
                .font(.body)
                .foregroundStyle(ink)
        }
    }
}
