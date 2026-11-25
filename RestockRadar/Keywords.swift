import Foundation

/// Sorts official-store listings by product type and set, using the words in the title.
enum Keywords {

    // MARK: Product types (what kind of sealed product)

    /// Checked in this order: the first match wins.
    static let kinds: [(name: String, pattern: String)] = [
        ("Ultra-Premium Collection", #"ultra[- ]premium"#),
        ("Premium Collection", #"premium collection"#),
        ("Elite Trainer Box", #"elite trainer box|\betb\b"#),
        ("Booster Box", #"booster (display )?box|display box|\b36 ?ct\b"#),
        ("Booster Bundle", #"booster bundle"#),
        ("Build & Battle Box", #"build (&|and) battle"#),
        ("ex Box / Collection Box", #"\bex box\b|collection box"#),
        ("Tin", #"\btins?\b"#),
        ("Blister", #"blister"#),
        ("Sleeved Booster / Pack", #"sleeved booster|booster pack|\bboosters?\b"#),
        ("Collection (binder, poster, figure…)", #"deck crafter|binder collection|poster collection|sticker collection|figure collection|knock out collection|illustration collection|portfolio"#),
        ("Battle Deck", #"\bdecks?\b"#),
        ("Collection (binder, poster, figure…)", #"collection"#),
    ]

    static var kindNames: [String] {
        var seen: [String] = []
        for k in kinds where !seen.contains(k.name) { seen.append(k.name) }
        return seen + ["Other"]
    }

    /// The types switched on the first time the app runs.
    static let defaultKinds: Set<String> = [
        "Elite Trainer Box", "Booster Box", "Booster Bundle", "Sleeved Booster / Pack",
        "Premium Collection", "Ultra-Premium Collection",
    ]

    // MARK: Sets (which expansion)

    /// Newest first. Checked in this order: the first match wins.
    static let sets: [(name: String, pattern: String)] = [
        ("Delta Reign", #"delta reign"#),
        ("30th Celebration", #"30th"#),
        ("Pitch Black", #"pitch black"#),
        ("Chaos Rising", #"chaos rising"#),
        ("Perfect Order", #"perfect order"#),
        ("Ascended Heroes", #"ascended heroes"#),
        ("Phantasmal Flames", #"phantasmal flames"#),
        ("Mega Evolution", #"mega evolution"#),
        ("Prismatic Evolutions", #"prismatic"#),
        ("Destined Rivals", #"destined rivals"#),
        ("Black Bolt", #"black bolt"#),
        ("White Flare", #"white flare"#),
        ("Journey Together", #"journey together"#),
        ("Surging Sparks", #"surging sparks"#),
        ("151", #"\b151\b"#),
        ("Paldean Fates", #"paldean fates"#),
        ("Deck Crafter's Collection", #"deck crafter"#),
    ]

    static let otherSet = "Other products"

    static var setNames: [String] { sets.map { $0.name } + [otherSet] }

    // MARK: Not card products (sold in the same store)

    static let accessoryPattern = #"deck shield|deck case|playmat|long card box|display frame|collection file|card key holder|card sleeve"#
    static let tcgPattern = #"trading card game|\btcg\b"#

    // MARK: Classify

    /// nil = not a card product (sleeves for cards, deck boxes, playmats, plush…).
    static func kind(of title: String) -> String? {
        let t = title.lowercased()
        if matches(t, accessoryPattern) || !matches(t, tcgPattern) { return nil }
        for k in kinds where matches(t, k.pattern) { return k.name }
        return "Other"
    }

    static func set(of title: String) -> String {
        let t = title.lowercased()
        for s in sets where matches(t, s.pattern) { return s.name }
        return otherSet
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Your selection (saved on the phone)

    static var selectedKinds: Set<String> {
        get {
            if let a = UserDefaults.standard.array(forKey: "selectedKinds") as? [String] { return Set(a) }
            return defaultKinds
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: "selectedKinds") }
    }

    static var selectedSets: Set<String> {
        get {
            if let a = UserDefaults.standard.array(forKey: "selectedSets") as? [String] { return Set(a) }
            return Set(setNames)
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: "selectedSets") }
    }

    static func isWanted(kind: String, set: String) -> Bool {
        selectedKinds.contains(kind) && selectedSets.contains(set)
    }
}
