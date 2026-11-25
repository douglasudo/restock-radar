import SwiftUI

/// Pick what to buy by keyword: product types × sets.
/// Every official-store product matching BOTH gets ticked, now and when new ones are listed.
struct KeywordsView: View {
    @EnvironmentObject private var store: ItemStore
    @Environment(\.dismiss) private var dismiss
    @State private var kinds: Set<String> = Keywords.selectedKinds
    @State private var sets: Set<String> = Keywords.selectedSets

    private func count(kind: String) -> Int {
        store.items.filter { $0.official && $0.group == kind }.count
    }

    private func count(set: String) -> Int {
        store.items.filter { $0.official && $0.setName == set }.count
    }

    private var matching: Int {
        store.items.filter { $0.official && kinds.contains($0.group) && sets.contains($0.setName) }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(matching) official product\(matching == 1 ? "" : "s") match right now. New listings that match are added and ticked automatically when the app scans the store.")
                        .font(.subheadline)
                }

                Section {
                    ForEach(Keywords.kindNames, id: \.self) { k in
                        Toggle(isOn: binding(for: k, in: $kinds)) {
                            HStack {
                                Text(k)
                                Spacer()
                                Text("\(count(kind: k))").foregroundColor(.secondary).font(.caption)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Product types")
                        Spacer()
                        Button(kinds.count == Keywords.kindNames.count ? "None" : "All") {
                            kinds = kinds.count == Keywords.kindNames.count ? [] : Set(Keywords.kindNames)
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                } footer: {
                    Text("Elite Trainer Box includes Pokémon Center ETBs. Booster Box means the 36-pack display. Sleeved Booster means single packs.")
                }

                Section {
                    ForEach(Keywords.setNames, id: \.self) { s in
                        Toggle(isOn: binding(for: s, in: $sets)) {
                            HStack {
                                Text(s)
                                Spacer()
                                let n = count(set: s)
                                Text(n == 0 ? "watching" : "\(n)")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Sets")
                        Spacer()
                        Button(sets.count == Keywords.setNames.count ? "None" : "All") {
                            sets = sets.count == Keywords.setNames.count ? [] : Set(Keywords.setNames)
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                } footer: {
                    Text("“watching” = the official store isn't selling this set right now (e.g. Prismatic Evolutions, 151). If it gets listed, the scan picks it up.")
                }
            }
            .navigationTitle("What to buy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Keywords.selectedKinds = kinds
                        Keywords.selectedSets = sets
                        store.applyKeywordSelection()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func binding(for value: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(value) },
            set: { on in
                if on { set.wrappedValue.insert(value) } else { set.wrappedValue.remove(value) }
            }
        )
    }
}
