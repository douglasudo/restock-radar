import SwiftUI
import UIKit

struct ItemDetailView: View {
    @EnvironmentObject private var store: ItemStore
    @EnvironmentObject private var monitor: Monitor
    @Environment(\.dismiss) private var dismiss
    @AppStorage("testMode") private var testMode = true
    @State private var confirmLiveBuy = false
    let itemID: UUID

    var body: some View {
        Group {
            if let item = store.item(id: itemID) {
                form(for: item)
            } else {
                Text("This item was deleted.")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Item")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Place a real order now?", isPresented: $confirmLiveBuy) {
            Button("Buy now", role: .destructive) {
                monitor.startBuy(itemID: itemID, reload: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Test mode is off, so this will try to buy 1 unit with your Lazada account right now.")
        }
    }

    /// Edits go straight into the saved item.
    private func binding<T>(_ keyPath: WritableKeyPath<WatchItem, T>, _ fallback: T) -> Binding<T> {
        Binding(
            get: { store.item(id: itemID)?[keyPath: keyPath] ?? fallback },
            set: { newValue in store.mutate(itemID) { $0[keyPath: keyPath] = newValue } }
        )
    }

    @MainActor
    private func form(for item: WatchItem) -> some View {
        Form {
            Section {
                HStack {
                    StatusPill(status: item.status, isChecking: monitor.currentItemID == item.id)
                    Spacer()
                    if let price = item.price {
                        Text(price).font(.headline)
                    }
                }
                if !item.lastNote.isEmpty {
                    Text(item.lastNote)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                CountdownText(item: item)
                LabeledContent("Checks so far", value: "\(item.checkCount)")
            } header: {
                Text("Status")
            }

            Section {
                Button {
                    monitor.checkNow(itemID)
                } label: {
                    Label("Check now", systemImage: "arrow.clockwise")
                }
                if let url = item.url {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Label("Open in Lazada", systemImage: "cart")
                    }
                    Button {
                        monitor.showInBrowser(url)
                    } label: {
                        Label("Show in the app's browser", systemImage: "safari")
                    }
                }
            }

            Section {
                TextField("Name", text: binding(\.name, ""))
                TextField("Link", text: binding(\.urlString, ""), axis: .vertical)
                    .font(.footnote)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("Ticked for the next run", isOn: binding(\.isEnabled, true))
                Toggle("Alert me if the price changes", isOn: binding(\.alertOnPriceChange, false))
            } header: {
                Text("Settings")
            }

            Section {
                Toggle("Auto-buy when back in stock", isOn: binding(\.autoBuy, false))
                    .disabled(item.maxPrice == nil)
                TextField("Max total you'll pay, e.g. 89.90", text: binding(\.maxPriceText, ""))
                    .keyboardType(.decimalPad)
                TextField("Option to pick, if it has choices", text: binding(\.variantText, ""))
                    .textInputAutocapitalization(.never)
                if let bought = item.boughtAt {
                    Text("Bought \(bought.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundColor(.green)
                    Button("Arm auto-buy again") {
                        store.mutate(itemID) {
                            $0.boughtAt = nil
                            $0.isEnabled = true
                        }
                    }
                }
                Button {
                    if testMode {
                        monitor.startBuy(itemID: itemID, reload: true)
                    } else {
                        confirmLiveBuy = true
                    }
                } label: {
                    Label(testMode ? "Test auto-buy now" : "Buy now (real order)", systemImage: "bolt.fill")
                }
                .disabled(item.maxPrice == nil || monitor.buying != nil)
            } header: {
                Text("Auto-buy")
            } footer: {
                Text("Set a max price first. When this item comes back in stock the app buys 1 unit using your Lazada default address and payment. It stops if the price or checkout total is above your max. Mode now: \(testMode ? "TEST (stops before Place Order)" : "LIVE (places real orders)"). Once bought, it moves off your list to “Bought”. Change test/live mode in Settings (gear icon on the main screen).")
            }

            Section {
                TextField("In-stock text, e.g. Add to Cart", text: binding(\.inStockKeyword, ""))
                    .textInputAutocapitalization(.never)
                TextField("Out-of-stock text, e.g. Out of Stock", text: binding(\.outOfStockKeyword, ""))
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Custom detection (optional)")
            } footer: {
                Text("Only fill these in if the automatic check gets this item wrong. The app looks for this exact text anywhere on the page. If both appear, out-of-stock wins.")
            }

            if let signals = monitor.lastSignals[itemID] {
                Section {
                    DisclosureGroup("What the app saw last time") {
                        SignalsView(signals: signals)
                    }
                }
            }

            Section {
                if item.history.isEmpty {
                    Text("No checks yet").foregroundColor(.secondary)
                }
                ForEach(item.history) { record in
                    HStack {
                        Text(record.date, style: .time)
                            .font(.caption.monospacedDigit())
                        StatusPill(status: record.status)
                        Spacer()
                        if let price = record.price {
                            Text(price).font(.caption)
                        }
                    }
                }
            } header: {
                Text("Recent checks")
            }

            Section {
                Button(role: .destructive) {
                    store.delete(id: itemID)
                    dismiss()
                } label: {
                    Label("Delete item", systemImage: "trash")
                }
            }
        }
    }
}

struct SignalsView: View {
    let signals: PageSignals

    private var buttonText: String {
        let buttons = signals.buttons ?? []
        if buttons.isEmpty { return "none found" }
        return buttons.prefix(25).map { $0.d ? "\($0.t) (greyed)" : $0.t }.joined(separator: " · ")
    }

    private var labelText: String {
        let labels = signals.labels ?? []
        return labels.isEmpty ? "none" : labels.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = signals.title {
                Text("Title: \(title)").font(.caption)
            }
            if let price = signals.price, !price.isEmpty {
                Text("Price: \(price)").font(.caption)
            }
            Text("Buttons: \(buttonText)").font(.caption)
            Text("Stock labels: \(labelText)").font(.caption)
            if let url = signals.url {
                Text(url)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
