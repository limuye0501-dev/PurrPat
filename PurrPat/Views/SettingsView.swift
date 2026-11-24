import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    var showPaywall: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Purr", isOn: $settings.purrEnabled)
                    Toggle("Show hand", isOn: $settings.handEnabled)
                    Picker("Sleeve", selection: $settings.handStyle) {
                        ForEach(HandStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                }
                Section {
                    slider("Size", value: $settings.catSize, range: 0.85...1.2)
                    slider("Chubbiness", value: $settings.chub, range: 0...1)
                }
                Section {
                    Toggle("Rain", isOn: rainBinding)
                }
                Section {
                    Button("Restore purchases") {
                        Task { await purchases.restore() }
                    }
                    if let message = purchases.lastMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: settings.handStyle) { old, new in
                guard !Entitlement.handStyleUnlocked(new, isPro: purchases.isPro) else { return }
                settings.handStyle = old
                showPaywall()
            }
        }
    }

    private var rainBinding: Binding<Bool> {
        Binding(
            get: { settings.rain },
            set: { on in
                if on && !purchases.isPro {
                    showPaywall()
                } else {
                    settings.rain = on
                }
            }
        )
    }

    private func slider(_ title: LocalizedStringKey, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Slider(value: value, in: range)
        }
    }
}
