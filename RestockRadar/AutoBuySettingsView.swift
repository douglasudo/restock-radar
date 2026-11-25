import SwiftUI

struct AutoBuySettingsView: View {
    @EnvironmentObject private var store: ItemStore
    @EnvironmentObject private var monitor: Monitor
    @Environment(\.dismiss) private var dismiss
    @AppStorage("testMode") private var testMode = true
    @AppStorage("buyMode") private var buyMode = "lazadaApp"
    @AppStorage("officialOnly") private var officialOnly = true
    @AppStorage("autoScan") private var autoScan = true
    @AppStorage("desktopMode") private var desktopMode = false
    @AppStorage("minInterval") private var minInterval = 45.0
    @AppStorage("maxInterval") private var maxInterval = 90.0
    @AppStorage("takeBreaks") private var takeBreaks = true
    @State private var confirmLive = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("When a ticked product is back", selection: $buyMode) {
                        Text("Open it in the Lazada app").tag("lazadaApp")
                        Text("Buy it automatically here").tag("autoBuy")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("When a ticked product is back")
                } footer: {
                    Text(buyMode == "lazadaApp"
                         ? "Restock Radar opens the product in the Lazada app instantly. You tap Buy Now → Place Order and approve payment. Nothing below this section is needed."
                         : "Restock Radar buys it inside its own Lazada browser (log in below once). Use Test mode first.")
                }

                Section {
                    Button {
                        dismiss()
                        monitor.openLogin(for: store.items)
                    } label: {
                        Label("Log in to Lazada", systemImage: "person.crop.circle")
                    }
                } header: {
                    Text("1. Log in once")
                } footer: {
                    Text("Restock Radar has its own browser, separate from the Lazada app, so log in here too. Use phone number or email; Google/Facebook login may not work inside apps. You stay logged in.")
                }

                Section {
                    Text("In Lazada, set a default delivery address and a default payment method. Auto-buy uses whatever Lazada picks by default.")
                    Text("Lazada Wallet or Cash on Delivery go straight through. Cards usually need a code from your bank. When that happens the app sounds the alarm and hands over to you on the payment screen.")
                        .foregroundColor(.secondary)
                } header: {
                    Text("2. Set your defaults")
                }
                .font(.subheadline)

                Section {
                    Toggle("Test mode", isOn: Binding(
                        get: { testMode },
                        set: { newValue in
                            if newValue { testMode = true } else { confirmLive = true }
                        }
                    ))
                } header: {
                    Text("3. Test, then go live")
                } footer: {
                    Text(testMode
                         ? "ON: the app goes all the way to checkout, then stops before Place Order. Nothing is bought. Open an item that's in stock and tap “Test auto-buy now”."
                         : "OFF: the app WILL place real orders with your account when an armed item comes back in stock.")
                }

                Section {
                    Toggle("Only the official Pokémon store", isOn: $officialOnly)
                    Toggle("Scan the official store for new products", isOn: $autoScan)
                } header: {
                    Text("Seller")
                } footer: {
                    Text("With the first switch on, the app only acts on products sold by \(Catalog.storeName). Anything you add by hand from another seller is checked but never opened or bought.")
                }

                Section {
                    Stepper("Shortest wait: \(Int(minInterval))s", value: $minInterval, in: 5...300, step: 5)
                    Stepper("Longest wait: \(Int(maxInterval))s", value: $maxInterval, in: 10...600, step: 5)
                    Toggle("Take a longer break now and then", isOn: $takeBreaks)
                } header: {
                    Text("Refresh timing")
                } footer: {
                    Text("Each product refreshes after a random wait between these two numbers, so it's never a steady beat. Shorter waits catch restocks sooner but make Lazada's slider check show up more often.")
                }
                .onChange(of: minInterval) { v in if maxInterval < v + 5 { maxInterval = v + 5 } }
                .onChange(of: maxInterval) { v in if minInterval > v - 5 { minInterval = max(5, v - 5) } }

                Section {
                    Toggle("Use Lazada's desktop website", isOn: $desktopMode)
                } footer: {
                    Text("Leave this off: the mobile site has the same Buy Now → Checkout → Place Order screens as the Lazada app. Turn it on only if pages won't load properly.")
                }

                Section {
                    Text("Buys 1 unit. Never pays more than the max price you set on each item. Each item is bought once, then moved off your list to “Bought”. The app must be open on screen to work.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Safety limits")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: desktopMode) { _ in
                monitor.applyUserAgent()
            }
            .alert("Turn on real buying?", isPresented: $confirmLive) {
                Button("Go live", role: .destructive) { testMode = false }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Armed items will be bought automatically with your Lazada account when they come back in stock.")
            }
        }
    }
}
