import Foundation

/// Raw facts read out of the product page by JavaScript.
struct PageSignals: Decodable {
    struct Button: Decodable {
        let t: String   // button text
        let d: Bool     // looks disabled / greyed out
    }
    var url: String?
    var title: String?
    var price: String?
    var text: String?
    var buttons: [Button]?
    var labels: [String]?
    var ready: String?
    var error: String?
}

struct DetectionResult {
    var status: StockStatus
    var price: String?
    var title: String?
    var note: String
    var officialSeller: Bool = false   // page names "Pokémon Store Online Singapore" as the seller
}

/// Decides "in stock / out of stock" from what the page shows.
enum Detector {

    // Words on an active button that mean "you can buy this now".
    static let buyWords = [
        "add to cart", "buy now", "add to bag",
        "beli sekarang", "tambah ke troli", "masukkan ke troli",      // MY / ID
        "mua ngay", "thêm vào giỏ",                                    // VN
        "ซื้อเลย", "ใส่รถเข็น", "เพิ่มไปยังรถเข็น",                         // TH
        "bilhin ngayon", "idagdag sa cart"                             // PH
    ]

    // Short labels/buttons that mean "you can't buy this now".
    static let outWords = [
        "out of stock", "sold out", "just sold out", "no longer available", "currently unavailable",
        "item unavailable", "product unavailable", "notify me",
        "stok habis", "hết hàng", "สินค้าหมด", "ubos na"
    ]

    // Buttons Lazada shows INSTEAD of Buy Now when sold out (seen on real SG screens).
    static let soldOutButtons = ["set reminder", "find similar products", "notify me", "sold out", "out of stock"]

    // Text on Lazada's anti-bot page.
    static let blockedWords = [
        "unusual traffic", "slide to verify", "please slide", "verify you are human",
        "are you a robot", "security verification", "captcha"
    ]

    static func decide(_ s: PageSignals, item: WatchItem) -> DetectionResult {
        let title = cleanTitle(s.title)
        let trimmedPrice = s.price?.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = (trimmedPrice?.isEmpty ?? true) ? nil : trimmedPrice

        let pageText = (s.text ?? "").lowercased()
        let official = pageText.contains("pokémon store online singapore") || pageText.contains("pokemon store online singapore")

        func result(_ status: StockStatus, _ note: String) -> DetectionResult {
            DetectionResult(status: status, price: price, title: title, note: note, officialSeller: official)
        }

        if let e = s.error { return result(.error, "Page script error: \(e)") }

        let url = (s.url ?? "").lowercased()
        let text = (s.text ?? "").lowercased()

        // 1. Anti-bot page?
        let blockedURL = ["punish", "captcha", "_____tmd_____"].contains { url.contains($0) }
        let blockedText = text.count < 4000 && blockedWords.contains { text.contains($0) }
        if blockedURL || blockedText {
            return result(.blocked, "Lazada showed a 'verify you're human' check")
        }

        // 1b. Dead link: Lazada's "not found" / delisted page.
        let deadPhrases = ["page not found", "product not found", "this product is no longer available",
                           "this product is no longer", "the page you requested", "sorry, the page", "item has been removed"]
        if text.count < 6000 && deadPhrases.contains(where: { text.contains($0) }) {
            return result(.error, "Broken link: Lazada says this product page doesn't exist any more")
        }

        // 2. The user's own keywords win.
        let outKey = item.outOfStockKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let inKey = item.inStockKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !outKey.isEmpty && text.contains(outKey) {
            return result(.outOfStock, "Found your out-of-stock text “\(item.outOfStockKeyword)”")
        }
        if !inKey.isEmpty && text.contains(inKey) {
            return result(.inStock, "Found your in-stock text “\(item.inStockKeyword)”")
        }

        let buttons = s.buttons ?? []
        let labels = s.labels ?? []

        // 3. Sold-out buttons ("Set Reminder", "Find similar products") replace Buy Now.
        if let b = buttons.first(where: { b in
            let low = b.t.lowercased()
            return soldOutButtons.contains { low.hasPrefix($0) }
        }) {
            return result(.outOfStock, "Page shows “\(b.t)” instead of Buy Now")
        }

        // 4. An active Buy Now / Add to Cart button = in stock.
        let buyButtons = buttons.filter { b in
            let low = b.t.lowercased()
            return buyWords.contains { low.contains($0) }
        }
        if let b = buyButtons.first(where: { !$0.d }) {
            return result(.inStock, "“\(b.t)” button is active")
        }
        if let b = buyButtons.first {
            return result(.outOfStock, "“\(b.t)” button is greyed out")
        }

        // 5. Otherwise a visible label like "Item chosen is out of stock" / "This item just sold out".
        if let label = labels.first(where: { l in
            let low = l.lowercased()
            return outWords.contains { low.contains($0) }
        }) {
            return result(.outOfStock, "Page shows “\(label)”")
        }

        // 6. Nothing conclusive.
        if text.count < 200 {
            return result(.unknown, "Page still loading")
        }
        return result(.unknown, "No Buy / Add to Cart button found. If this keeps happening, set custom detection text for this item.")
    }

    static func cleanTitle(_ raw: String?) -> String? {
        guard var t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if let r = t.range(of: " | ") { t = String(t[..<r.lowerBound]) }
        if t.lowercased().hasPrefix("lazada") { return nil }
        if t.count > 90 { t = String(t.prefix(90)) + "…" }
        return t
    }

    /// Runs inside the product page. Always returns a JSON string.
    static let script = #"""
    (function () {
      try {
        function clean(s) { return (s || '').replace(/\s+/g, ' ').trim(); }
        function visible(el) {
          if (!el || !el.getClientRects || el.getClientRects().length === 0) return false;
          var cs = window.getComputedStyle(el);
          return !(cs && (cs.visibility === 'hidden' || cs.display === 'none'));
        }
        var body = document.body;
        var text = body ? (body.innerText || '') : '';

        var og = document.querySelector('meta[property="og:title"]');
        var h1 = document.querySelector('h1, .pdp-mod-product-badge-title, [class*="product-title"], [class*="productTitle"]');
        var title = clean((h1 && h1.innerText) || (og && og.content) || document.title);

        var sel = 'button, [role="button"], a, input[type="submit"], [class*="btn"], [class*="Btn"], ' +
                  '[class*="button"], [class*="Button"], [class*="cart"], [class*="Cart"], [class*="buy"], [class*="Buy"]';
        var nodes = body ? body.querySelectorAll(sel) : [];
        var buttons = [];
        var seenBtn = {};
        for (var i = 0; i < nodes.length && buttons.length < 400; i++) {
          var el = nodes[i];
          var t = clean(el.innerText || el.value || el.getAttribute('aria-label'));
          if (!t || t.length > 40) continue;
          if (!visible(el)) continue;
          var cls = (typeof el.className === 'string') ? el.className : '';
          var disabled = !!el.disabled || el.getAttribute('aria-disabled') === 'true' || /disable/i.test(cls);
          var key = t + '|' + disabled;
          if (seenBtn[key]) continue;
          seenBtn[key] = true;
          buttons.push({ t: t, d: disabled });
        }

        var labels = [];
        if (body) {
          var re = /stock|sold out|available|notify|habis|hết hàng|สินค้าหมด|ubos/i;
          var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, null);
          var n, count = 0;
          while ((n = walker.nextNode()) && labels.length < 30 && count < 30000) {
            count++;
            var v = clean(n.nodeValue);
            if (!v || v.length > 60 || !re.test(v)) continue;
            var pe = n.parentElement;
            if (!pe || /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)$/.test(pe.tagName)) continue;
            if (!visible(pe)) continue;
            labels.push(v);
          }
        }

        var priceSel = ['.pdp-price_type_normal', '.pdp-v2-product-price-content-salePrice-amount',
                        '[class*="salePrice"]', '[class*="sale-price"]', '.pdp-price', '[class*="price"]'];
        var price = '';
        for (var j = 0; j < priceSel.length && !price; j++) {
          var ps = document.querySelectorAll(priceSel[j]);
          for (var k = 0; k < ps.length; k++) {
            var pt = clean(ps[k].innerText);
            if (/\d/.test(pt) && pt.length < 30 && visible(ps[k])) { price = pt; break; }
          }
        }
        if (!price) {
          var m = text.match(/(S\$|RM|₱|฿|Rp|₫|\$)\s?\d[\d.,]*/);
          if (m) price = m[0];
        }

        return JSON.stringify({
          url: location.href, title: title, price: price,
          text: text.slice(0, 60000), buttons: buttons, labels: labels,
          ready: document.readyState
        });
      } catch (e) {
        return JSON.stringify({ error: String(e) });
      }
    })();
    """#
}
