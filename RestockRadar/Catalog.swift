import Foundation

/// Pokémon TCG products sold by the OFFICIAL "Pokémon Store Online Singapore" on Lazada
/// (the store Pokémon Singapore links to: https://s.lazada.sg/a.0S2bl).
/// Captured from the store's own "trading card game" listing (all pages) on 25 Nov 2026.
/// Accessories with no cards (deck shields, deck cases, playmats, card boxes, frames) were left out.
/// Product type and set are worked out from each title by `Keywords`.
struct CatalogItem: Identifiable, Hashable {
    let id: String        // Lazada item ID
    let title: String
    let price: String     // official price on the date above

    var url: String { "https://www.lazada.sg/products/pdp-i\(id).html" }
    var kind: String { Keywords.kind(of: title) ?? "Other" }
    var set: String { Keywords.set(of: title) }
}

enum Catalog {
    static let version = 2
    static let collectedOn = "25 Nov 2026"
    static let storeName = "Pokémon Store Online Singapore"
    static let storeLink = "https://s.lazada.sg/a.0S2bl"
    /// The official store's own search, used by "Scan official store".
    static func storeSearchURL(page: Int) -> URL {
        URL(string: "https://www.lazada.sg/pokemon-store-online-singapore/?from=wangpu&q=trading%20card%20game&langFlag=en&pageTypeId=2&page=\(page)")!
    }

    static let items: [CatalogItem] = [
        CatalogItem(id: "13855587802", title: "Pokémon Trading Card Game: 30th Celebration 2-Pack Blister", price: "$16.90"),
        CatalogItem(id: "13930293275", title: "Pokémon Trading Card Game: Mini Portfolio", price: "$9.40"),
        CatalogItem(id: "13718919969", title: "Pokémon Trading Card Game: Mega Evolution: Chaos Rising Sleeved Boosters", price: "$6.90"),
        CatalogItem(id: "13992117535", title: "Pokémon Trading Card Game: 30th Celebration Ultra-Premium Collection - Day", price: "$329.90"),
        CatalogItem(id: "13930299333", title: "Pokémon Trading Card Game: Enhanced 2-Pack Blister", price: "$20.90"),
        CatalogItem(id: "13992083626", title: "Pokémon Trading Card Game: Mega Evolution - Delta Reign Pokémon Center Elite Trainer Box", price: "$109.90"),
        CatalogItem(id: "13858112099", title: "Pokémon Trading Card Game: 30th Celebration Tech Sticker Collection (Alolan Exeggutor)", price: "$27.90"),
        CatalogItem(id: "13858092221", title: "Pokémon Trading Card Game: 30th Celebration ex Box (Sylveon Ex)", price: "$39.90"),
        CatalogItem(id: "13992053733", title: "Pokémon Trading Card Game: 30th Celebration Ditto Premium Collection", price: "$72.90"),
        CatalogItem(id: "13992139346", title: "Pokémon Trading Card Game: 30th Celebration Ultra-Premium Collection - Night", price: "$329.90"),
        CatalogItem(id: "13855645417", title: "Pokémon Trading Card Game: 30th Celebration ex Tin (Standard) (Greninja Ex)", price: "$39.90"),
        CatalogItem(id: "13964499174", title: "Pokémon Trading Card Game: Deck Crafter's Collection", price: "$18.90"),
        CatalogItem(id: "13664261034", title: "Pokémon Center Trading Card Game: Mega Evolution: Perfect Order Pokémon Center Elite Trainer Box", price: "$109.90"),
        CatalogItem(id: "13858060495", title: "Pokémon Trading Card Game: 30th Celebration Binder Collection", price: "$58.90"),
        CatalogItem(id: "13858076401", title: "Pokémon Trading Card Game: 30th Celebration Knock Out Collection", price: "$16.90"),
        CatalogItem(id: "13855641431", title: "Pokémon Trading Card Game: 30th Celebration Poster Collection", price: "$27.90"),
        CatalogItem(id: "13855645416", title: "Pokémon Trading Card Game: 30th Celebration ex Box (Greninja Ex)", price: "$39.90"),
        CatalogItem(id: "13858018841", title: "Pokémon Trading Card Game: 30th Celebration Pokémon Center Elite Trainer Box", price: "$109.90"),
        CatalogItem(id: "13771531478", title: "Pokémon Trading Card Game: Mega Evolution: Pitch Black Build & Battle Box", price: "$39.90"),
        CatalogItem(id: "13983350458", title: "Pokémon Trading Card Game: 30th Celebration Battle Deck (Umbreon)", price: "$34.90"),
        CatalogItem(id: "13855633456", title: "Pokémon Trading Card Game: 30th Celebration ex Tin (Standard) (Sylveon Ex)", price: "$39.90"),
        CatalogItem(id: "13858046508", title: "Pokémon Trading Card Game: 30th Celebration Tech Sticker Collection (Lucario)", price: "$27.90"),
        CatalogItem(id: "13773062548", title: "Pokémon Trading Card Game: Mega Evolution - Pitch Black Sleeved Boosters", price: "$6.90"),
        CatalogItem(id: "13995494582", title: "Pokémon Trading Card Game: Mega Greninja ex League Battle Deck", price: "$54.90"),
        CatalogItem(id: "3653828471", title: "Pokémon Trading Card Game: Mega Evolution: Ascended Heroes Mini Tin", price: "$18.90"),
        CatalogItem(id: "13718957724", title: "Pokémon Trading Card Game: Mega Lucario ex League Battle Deck", price: "$54.90"),
        CatalogItem(id: "13688582442", title: "Pokémon Trading Card Game: Mega Evolution: Perfect Order Build & Battle Box", price: "$39.90"),
        CatalogItem(id: "13771481735", title: "Pokémon Trading Card Game: Mega Evolution - Pitch Black Pokémon Center Elite Trainer Box", price: "$109.90"),
        CatalogItem(id: "13718947810", title: "Pokémon Trading Card Game: Mega Evolution: Chaos Rising Pokémon Center Elite Trainer Box", price: "$109.90"),
        CatalogItem(id: "13933878257", title: "Pokémon Trading Card Game: 30th Celebration Booster Bundle - Bulk", price: "$41.40"),
        CatalogItem(id: "14001562460", title: "[Standard Edition] Pokémon Trading Card Game Mega Evolution: Perfect Order Elite Trainer Box", price: "$89.90"),
        CatalogItem(id: "13664788472", title: "Pokémon Center Trading Card Game: Mega Evolution: Perfect Order Sleeved Booster", price: "$6.90"),
        CatalogItem(id: "13992161254", title: "Pokémon Trading Card Game: Mega Evolution - Delta Reign Sleeved Booster", price: "$6.90"),
        CatalogItem(id: "13995482685", title: "Pokémon Trading Card Game: 30th Celebration Figure Collection - Night", price: "$54.90"),
        CatalogItem(id: "13930327128", title: "Pokémon Trading Card Game: 30th Celebration Mini Tins", price: "$16.90"),
        CatalogItem(id: "14028369833", title: "Pokémon Trading Card Game Mega Evolution: Delta Reign Build & Battle Box", price: "$39.90"),
        CatalogItem(id: "13696744288", title: "Pokémon Trading Card Game Mega Evolution: Ascended Heroes Booster Bundle", price: "$41.40"),
        CatalogItem(id: "13995464773", title: "Pokémon Trading Card Game: 30th Celebration Figure Collection - Day", price: "$54.90"),
        CatalogItem(id: "13995598761", title: "Pokémon Trading Card Game: Mega Evolution - Delta Reign 36 CT Booster Display Box", price: "$248.40"),
        CatalogItem(id: "13752580851", title: "Pokémon Trading Card Game: First Partner Illustration Collection Series 2", price: "$27.90"),
        CatalogItem(id: "13979931603", title: "Pokémon Trading Card Game: 30th Celebration Battle Deck (Espeon)", price: "$34.90"),
        CatalogItem(id: "13737417088", title: "Pokémon Trading Card Game: Lumiose City Mini Tin", price: "$18.90"),
        CatalogItem(id: "13696710585", title: "Pokémon Trading Card Game Mega Evolution: Ascended Heroes ex Box (Mega Emboar ex)", price: "$39.90"),
        CatalogItem(id: "13718955701", title: "Pokémon Trading Card Game: Mega Evolution: Chaos Rising Booster Display Box", price: "$248.40"),
        CatalogItem(id: "13737333275", title: "Pokémon Trading Card Game: Mega Moonlit Tin", price: "$39.90"),
        CatalogItem(id: "13738890220", title: "Pokémon Trading Card Game: Mega Evolution - Chaos Rising Build & Battle Box", price: "$39.90"),
        CatalogItem(id: "13696652880", title: "Pokémon Trading Card Game: Ascended Heroes ex Box (Mega Feraligatr ex)", price: "$39.90"),
        CatalogItem(id: "13696682681", title: "Pokémon Trading Card Game: Ascended Heroes ex Box (Mega Meganium ex)", price: "$39.90"),
        CatalogItem(id: "13771595020", title: "Pokémon Trading Card Game Mega Evolution - Pitch Black Booster Display Box", price: "$248.40"),
        CatalogItem(id: "13786865113", title: "Pokémon Trading Card Game: First Partner Illustration Collection Series 3", price: "$27.90"),
        CatalogItem(id: "13773124136", title: "Pokémon Trading Card Game: Mega Greninja ex Premium Collection", price: "$72.90"),
        CatalogItem(id: "13738878466", title: "Pokémon Trading Card Game: 2025 World Championship Decks [Liao Fu Guan]", price: "$34.90"),
        CatalogItem(id: "13739004067", title: "Pokémon Trading Card Game: 2025 World Championship Decks [Jose Cruz Galindo - Resendiz]", price: "$34.90"),
        CatalogItem(id: "13736931772", title: "Pokémon Trading Card Game: 2025 World Championship Decks [Riley McKay]", price: "$34.90"),
        CatalogItem(id: "13737197220", title: "Pokémon Trading Card Game: 2025 World Championship Decks [Yuya Okita]", price: "$34.90"),
    ]
}
