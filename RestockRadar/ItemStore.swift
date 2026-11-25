import Foundation
import Combine

/// Keeps the list of watched items and saves it to the phone.
final class ItemStore: ObservableObject {
    @Published private(set) var items: [WatchItem] = []
    @Published private(set) var purchases: [PurchaseRecord] = []
    private let fileURL: URL
    private let purchasesURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("watch-items.json")
        purchasesURL = dir.appendingPathComponent("purchases.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([WatchItem].self, from: data) {
            items = decoded
        }
        if let data = try? Data(contentsOf: purchasesURL),
           let decoded = try? JSONDecoder().decode([PurchaseRecord].self, from: data) {
            purchases = decoded
        }
    }

    /// Moves a bought item off the list and into "Bought".
    func recordPurchase(of id: UUID) {
        guard let item = item(id: id) else { return }
        purchases.insert(PurchaseRecord(name: item.displayName, urlString: item.urlString,
                                        price: item.price, date: Date()), at: 0)
        savePurchases()
        delete(id: id)
    }

    func clearPurchase(id: UUID) {
        purchases.removeAll { $0.id == id }
        savePurchases()
    }

    /// Brings in the official-store catalog. Earlier non-official catalog entries are removed
    /// (products you added yourself are kept). New products are ticked if they match your keywords.
    @discardableResult
    func importCatalog() -> Int {
        items.removeAll { !$0.group.isEmpty && !$0.official }
        let existing = Set(items.compactMap { $0.lazadaItemID })
        var added = 0
        for c in Catalog.items where !existing.contains(c.id) {
            items.append(makeOfficialItem(id: c.id, title: c.title, price: c.price))
            added += 1
        }
        save()
        UserDefaults.standard.set(Catalog.version, forKey: "catalogImportedVersion")
        return added
    }

    /// First launch (or a newer catalog): bring the catalog in automatically.
    func importCatalogIfNeeded() {
        let done = UserDefaults.standard.integer(forKey: "catalogImportedVersion")
        if done < Catalog.version { importCatalog() }
    }

    private func makeOfficialItem(id: String, title: String, price: String?) -> WatchItem {
        var item = WatchItem(name: title, urlString: "https://www.lazada.sg/products/pdp-i\(id).html")
        item.group = Keywords.kind(of: title) ?? "Other"
        item.setName = Keywords.set(of: title)
        item.official = true
        item.price = price
        item.isEnabled = Keywords.isWanted(kind: item.group, set: item.setName)
        return item
    }

    /// Adds products found by "Scan official store" that aren't on the list yet.
    /// Returns the new items (already ticked if they match your keywords).
    func mergeDiscovered(_ found: [(id: String, title: String, price: String)]) -> [WatchItem] {
        let existing = Set(items.compactMap { $0.lazadaItemID })
        var added: [WatchItem] = []
        for f in found where !existing.contains(f.id) && Keywords.kind(of: f.title) != nil {
            let item = makeOfficialItem(id: f.id, title: f.title, price: f.price.isEmpty ? nil : f.price)
            items.append(item)
            added.append(item)
        }
        if !added.isEmpty { save() }
        return added
    }

    /// Re-ticks official products to match the chosen sets and product types.
    func applyKeywordSelection() {
        for i in items.indices where items[i].official {
            items[i].isEnabled = Keywords.isWanted(kind: items[i].group, set: items[i].setName)
        }
        save()
    }

    func setGroupSelected(_ group: String, _ selected: Bool) {
        for i in items.indices where items[i].group == group { items[i].isEnabled = selected }
        save()
    }

    @discardableResult
    func removeBrokenLinks() -> Int {
        let before = items.count
        items.removeAll { $0.linkStatus == "broken" }
        save()
        return before - items.count
    }

    /// Section order: product types in a fixed order, then your own products.
    var groups: [String] {
        var seen: [String] = []
        for s in Keywords.kindNames where items.contains(where: { $0.group == s }) { seen.append(s) }
        for g in items.map({ $0.group }) where !seen.contains(g) { seen.append(g) }
        return seen
    }

    func setAllSelected(_ selected: Bool) {
        for i in items.indices { items[i].isEnabled = selected }
        save()
    }

    private func savePurchases() {
        if let data = try? JSONEncoder().encode(purchases) {
            try? data.write(to: purchasesURL, options: .atomic)
        }
    }

    func item(id: UUID) -> WatchItem? {
        items.first { $0.id == id }
    }

    func add(_ item: WatchItem) {
        items.append(item)
        save()
    }

    func update(_ item: WatchItem) {
        guard let i = index(of: item.id) else { return }
        items[i] = item
        save()
    }

    func mutate(_ id: UUID, _ change: (inout WatchItem) -> Void) {
        guard let i = index(of: id) else { return }
        change(&items[i])
        save()
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        var copy = items
        let moving = source.sorted().map { copy[$0] }
        for i in source.sorted(by: >) { copy.remove(at: i) }
        let shift = source.filter { $0 < destination }.count
        copy.insert(contentsOf: moving, at: destination - shift)
        items = copy
        save()
    }

    private func index(of id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("RestockRadar: save failed: \(error)")
        }
    }
}
