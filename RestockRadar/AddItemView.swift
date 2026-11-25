import SwiftUI
import UIKit

struct AddItemView: View {
    @EnvironmentObject private var store: ItemStore
    @EnvironmentObject private var monitor: Monitor
    @Environment(\.dismiss) private var dismiss

    @State private var link = ""
    @State private var name = ""
    @State private var autoBuy = true
    @State private var maxPrice = ""
    @State private var option = ""
    @State private var errorText: String?
    @AppStorage("buyMode") private var buyMode = "lazadaApp"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://www.lazada.sg/products/…", text: $link, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        if let pasted = UIPasteboard.general.string {
                            link = pasted
                        }
                    } label: {
                        Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Lazada link")
                } footer: {
                    Text("In the Lazada app: open the product, tap Share, then Copy Link. Short links (s.lazada.sg/…) work too.")
                }

                Section {
                    TextField("e.g. Pokémon TCG Elite Trainer Box", text: $name)
                } header: {
                    Text("Name (optional)")
                } footer: {
                    Text("Leave blank and the app fills in the product name after its first check.")
                }

                if buyMode == "autoBuy" {
                Section {
                    Toggle("Auto-buy when it's back", isOn: $autoBuy)
                    if autoBuy {
                        TextField("Max total you'll pay, e.g. 89.90", text: $maxPrice)
                            .keyboardType(.decimalPad)
                        TextField("Option to pick, only if it has choices", text: $option)
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Text("When it's in stock")
                } footer: {
                    Text(autoBuy
                         ? "Buys 1 unit with your Lazada default address and payment, and never above your max. Once bought, it's removed from your list."
                         : "Alert only: loud alarm and notification, and you buy it yourself.")
                }
                }

                if let errorText = errorText {
                    Section {
                        Text(errorText).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @MainActor
    private func add() {
        guard let url = LinkParser.extractURL(from: link) else {
            errorText = "That doesn't look like a link. Copy the product link from Lazada and paste it here."
            return
        }
        let useAutoBuy = buyMode == "autoBuy" && autoBuy
        if useAutoBuy && PriceParser.parse(maxPrice) == nil {
            errorText = "Enter the most you'll pay (for example 89.90), or switch off auto-buy."
            return
        }
        var item = WatchItem(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                             urlString: url.absoluteString)
        item.autoBuy = useAutoBuy
        item.maxPriceText = useAutoBuy ? maxPrice.trimmingCharacters(in: .whitespaces) : ""
        item.variantText = useAutoBuy ? option.trimmingCharacters(in: .whitespaces) : ""
        store.add(item)
        monitor.checkNow(item.id)   // first look: fills in name, price and stock
        dismiss()
    }
}
