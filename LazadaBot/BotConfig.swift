import Foundation

// ─────────────────────────────────────────────────────────────
//  EDIT THIS FILE, then press ⌘U with the "LazadaBot" scheme.
// ─────────────────────────────────────────────────────────────
enum BotConfig {

    /// The product's FULL link, e.g. https://www.lazada.sg/products/pokemon-tcg-...-i123456-s789.html
    /// (If Lazada gives you a short s.lazada.sg link, open it in Safari once and copy the long one.)
    static let productLink = "https://www.lazada.sg/products/PASTE-YOUR-PRODUCT-LINK-HERE.html"

    /// Most you'll pay in total (including shipping). The bot won't buy above this.
    static let maxPrice: Double = 90.00

    /// Only if the product has choices: the option's exact words, e.g. "Elite Trainer Box". Otherwise "".
    static let option = ""

    /// Seconds to wait between refreshes. 3 is fast; go higher if Lazada starts complaining.
    static let refreshEverySeconds: Double = 3

    /// false = TEST: goes all the way to checkout, then stops before Place Order.
    /// true  = LIVE: places the order and presses Pay.
    static let placeRealOrder = false

    /// Give up after this many hours of watching.
    static let maxRunHours: Double = 12
}
