import Foundation

/// What the app thinks about an item's stock after a check.
enum StockStatus: String, Codable {
    case unknown
    case inStock
    case outOfStock
    case blocked      // Lazada showed a "verify you're human" page
    case error

    var label: String {
        switch self {
        case .unknown: return "Not sure yet"
        case .inStock: return "IN STOCK"
        case .outOfStock: return "Out of stock"
        case .blocked: return "Verify needed"
        case .error: return "Error"
        }
    }
}

/// One row in an item's "Recent checks" list.
struct CheckRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var status: StockStatus
    var price: String?
    var note: String
}

/// A Lazada product the user wants watched.
struct WatchItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var urlString: String
    var intervalSeconds: Int = 60
    var isEnabled: Bool = true
    var inStockKeyword: String = ""
    var outOfStockKeyword: String = ""
    var alertOnPriceChange: Bool = false

    // Auto-buy
    var autoBuy: Bool = false
    var maxPriceText: String = ""
    var variantText: String = ""
    var boughtAt: Date?

    // Catalog / grouping
    var group: String = ""          // product type, e.g. "Elite Trainer Box"; "" = added by you
    var setName: String = ""        // e.g. "Delta Reign"
    var official: Bool = false      // listed by the official Pokémon Store Online Singapore
    var linkStatus: String = ""     // "" not checked yet, "ok", "broken"

    // Results of the latest check
    var status: StockStatus = .unknown
    var lastDefiniteStatus: StockStatus = .unknown   // last time we were sure (in or out)
    var price: String?
    var lastChecked: Date?
    var lastNote: String = ""
    var checkCount: Int = 0
    var history: [CheckRecord] = []

    var url: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    var maxPrice: Double? {
        let t = maxPriceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let v = PriceParser.parse(t), v > 0 else { return nil }
        return v
    }

    /// Lazada's item number from the link (…-i14035123813.html), used to avoid duplicates.
    var lazadaItemID: String? {
        guard let r = urlString.range(of: #"-i(\d+)"#, options: .regularExpression) else { return nil }
        return String(urlString[r].dropFirst(2))
    }

    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        return url?.host ?? "New item"
    }
}

/// Something the app bought for you (the item itself is removed from the list).
struct PurchaseRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var urlString: String
    var price: String?
    var date: Date
}

/// Tolerant loading: fields added in later versions get their default value.
extension WatchItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WatchItem(urlString: "")
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        urlString = try c.decodeIfPresent(String.self, forKey: .urlString) ?? d.urlString
        intervalSeconds = try c.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? d.intervalSeconds
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        inStockKeyword = try c.decodeIfPresent(String.self, forKey: .inStockKeyword) ?? d.inStockKeyword
        outOfStockKeyword = try c.decodeIfPresent(String.self, forKey: .outOfStockKeyword) ?? d.outOfStockKeyword
        alertOnPriceChange = try c.decodeIfPresent(Bool.self, forKey: .alertOnPriceChange) ?? d.alertOnPriceChange
        autoBuy = try c.decodeIfPresent(Bool.self, forKey: .autoBuy) ?? d.autoBuy
        maxPriceText = try c.decodeIfPresent(String.self, forKey: .maxPriceText) ?? d.maxPriceText
        variantText = try c.decodeIfPresent(String.self, forKey: .variantText) ?? d.variantText
        boughtAt = try c.decodeIfPresent(Date.self, forKey: .boughtAt)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? d.group
        setName = try c.decodeIfPresent(String.self, forKey: .setName) ?? d.setName
        official = try c.decodeIfPresent(Bool.self, forKey: .official) ?? d.official
        linkStatus = try c.decodeIfPresent(String.self, forKey: .linkStatus) ?? d.linkStatus
        status = try c.decodeIfPresent(StockStatus.self, forKey: .status) ?? d.status
        lastDefiniteStatus = try c.decodeIfPresent(StockStatus.self, forKey: .lastDefiniteStatus) ?? d.lastDefiniteStatus
        price = try c.decodeIfPresent(String.self, forKey: .price)
        lastChecked = try c.decodeIfPresent(Date.self, forKey: .lastChecked)
        lastNote = try c.decodeIfPresent(String.self, forKey: .lastNote) ?? d.lastNote
        checkCount = try c.decodeIfPresent(Int.self, forKey: .checkCount) ?? d.checkCount
        history = try c.decodeIfPresent([CheckRecord].self, forKey: .history) ?? d.history
    }
}

/// The full-screen alert: plain "in stock" or the result of an auto-buy.
struct AlarmInfo: Identifiable, Equatable {
    enum Kind: Equatable {
        case inStock, ordered, testRun, needsYou, failed

        var title: String {
            switch self {
            case .inStock: return "IN STOCK!"
            case .ordered: return "ORDER PLACED!"
            case .testRun: return "Test run worked"
            case .needsYou: return "Your turn, quick!"
            case .failed: return "Auto-buy stopped"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let itemID: UUID
    let name: String
    let url: URL?
    let price: String?
    let message: String?
}

/// Pulls the first web link out of whatever the user pasted
/// (Lazada's share text has extra words around the link).
enum LinkParser {
    static func extractURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            let urls = detector.matches(in: trimmed, options: [], range: range).compactMap { $0.url }
            if let url = urls.first(where: { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }) {
                return url
            }
        }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme.hasPrefix("http") {
            return url
        }
        return nil
    }
}
