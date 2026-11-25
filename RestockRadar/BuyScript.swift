import Foundation

/// What the buy flow sees on the current page.
struct BuySnapshot: Decodable {
    var stage: String          // product, checkout, payment, needsInput, login, verify, success, unknown
    var url: String?
    var calculating: Bool?     // "Place Order  Calculating…" — total not ready yet
    var soldOut: Bool?         // "This item just sold out" / "Item chosen is out of stock"
    var total: String?
    var price: String?
    var error: String?
}

/// JavaScript used by the auto-buy flow. It works by matching the words on buttons
/// ("Buy Now", "Place Order", "Pay Now") rather than Lazada's internal code names,
/// so small design changes on Lazada are less likely to break it.
enum BuyScript {

    // Earlier entries win. "Confirm"/"OK" cover the options pop-up on the mobile site.
    static let buyPatterns = ["^confirm$", "^ok$", "^buy now$"]
    static let placeOrderPatterns = ["^place order", "^proceed to pay", "^place your order"]
    static let payPatterns = ["^pay now", "^confirm order", "^confirm payment", "^place order", "^pay$"]

    static func variantPatterns(_ text: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: text)
        return ["^" + escaped + "$", escaped]
    }

    static let snapshot = #"""
    (function () {
      try {
        function clean(s) { return (s || '').replace(/\s+/g, ' ').trim(); }
        function visible(el) {
          if (!el || !el.getClientRects || el.getClientRects().length === 0) return false;
          var cs = window.getComputedStyle(el);
          return !(cs && (cs.visibility === 'hidden' || cs.display === 'none'));
        }
        function hasButton(re) {
          var els = document.querySelectorAll('button, [role="button"], a, [class*="btn"], [class*="Btn"], [class*="button"], [class*="Button"]');
          for (var i = 0; i < els.length; i++) {
            var t = clean(els[i].innerText);
            if (t && t.length <= 40 && re.test(t) && visible(els[i])) return true;
          }
          return false;
        }
        var url = location.href;
        var lurl = url.toLowerCase();
        var text = document.body ? (document.body.innerText || '') : '';
        var low = text.toLowerCase();
        var lines = text.split('\n').map(clean).filter(function (l) { return l.length > 0; });
        var checkoutTitle = lines.some(function (l) { return /^checkout$/i.test(l); });
        var calculating = /place order\s*calculating/i.test(lines.join(' ')) || hasButton(/calculating/i);
        var soldOut = /this item just sold out|item chosen is out of stock/.test(low);

        var inputs = document.querySelectorAll('input');
        var needsInput = false, hasPassword = false;
        for (var i = 0; i < inputs.length; i++) {
          var inp = inputs[i];
          if (!visible(inp)) continue;
          var attrs = ((inp.name || '') + ' ' + (inp.id || '') + ' ' + (inp.placeholder || '') + ' ' +
                       (inp.getAttribute('aria-label') || '')).toLowerCase();
          if (inp.type === 'password') hasPassword = true;
          if (/\b(otp|cvv|cvc|pin)\b|security code|one.?time/.test(attrs)) needsInput = true;
        }

        var stage = 'unknown';
        if (/punish|captcha|_____tmd_____/.test(lurl) ||
            (low.length < 4000 && /unusual traffic|slide to verify|please slide|verify you are human/.test(low))) {
          stage = 'verify';
        } else if (/member\.lazada\.|\/user\/login|\/login/.test(lurl)) {
          stage = 'login';
        } else if (/thank you for your order|your order has been placed|order placed successfully|payment successful|payment success|thank you for shopping/.test(low) ||
                   /thank-?you|\/success|paysuccess/.test(lurl)) {
          stage = 'success';
        } else if (needsInput || /enter (the )?otp|one-time password|enter (your )?cvv|enter your pin|3-?d secure/.test(low)) {
          stage = 'needsInput';
        } else if (/cashier|\/payment/.test(lurl) ||
                   (/payment method/.test(low) && hasButton(/^(pay now|confirm order|confirm payment)/i))) {
          stage = 'payment';
        } else if (/checkout\.lazada|\/checkout|\/shipping/.test(lurl) || checkoutTitle || hasButton(/^(place order|proceed to pay)/i)) {
          stage = 'checkout';
        } else if (hasPassword && /log ?in|sign ?in/.test(low)) {
          stage = 'login';
        } else if (/\/products\/|-i\d+(-s\d+)?\.html|pdp/.test(lurl) || hasButton(/^(buy now|add to cart)$/i)) {
          stage = 'product';
        }

        var money = /(S\$|RM|₱|฿|Rp|₫|\$)\s?\d[\d.,]*/;
        var total = '';
        for (var j = 0; j < lines.length; j++) {
          if (/^(total|grand total|order total|total payment|total amount)\b/i.test(lines[j])) {
            for (var k = j; k < Math.min(j + 3, lines.length); k++) {
              var m = lines[k].match(money);
              if (m) { total = m[0]; break; }
            }
          }
        }

        var priceSel = ['.pdp-price_type_normal', '.pdp-v2-product-price-content-salePrice-amount',
                        '[class*="salePrice"]', '[class*="sale-price"]', '.pdp-price', '[class*="price"]'];
        var price = '';
        for (var p = 0; p < priceSel.length && !price; p++) {
          var ps = document.querySelectorAll(priceSel[p]);
          for (var q = 0; q < ps.length; q++) {
            var pt = clean(ps[q].innerText);
            if (/\d/.test(pt) && pt.length < 30 && visible(ps[q])) { price = pt; break; }
          }
        }

        return JSON.stringify({ stage: stage, url: url, total: total, price: price,
                                calculating: calculating, soldOut: soldOut });
      } catch (e) {
        return JSON.stringify({ stage: 'unknown', error: String(e) });
      }
    })();
    """#

    /// Called as (clickFunction)(patterns, preferLast, mode, maxLength).
    /// mode 0 = normal click, mode 1 = simulated finger tap (for touch-only buttons).
    static let clickFunction = #"""
    function (pats, preferLast, mode, maxLen) {
      try {
        function clean(s) { return (s || '').replace(/\s+/g, ' ').trim(); }
        function visible(el) {
          if (!el || !el.getClientRects || el.getClientRects().length === 0) return false;
          var cs = window.getComputedStyle(el);
          return !(cs && (cs.visibility === 'hidden' || cs.display === 'none'));
        }
        var res = pats.map(function (p) { return new RegExp(p, 'i'); });
        var all = document.body ? document.body.getElementsByTagName('*') : [];
        var best = null, bestRank = 999, bestText = '';
        for (var i = 0; i < all.length; i++) {
          var el = all[i];
          var tc = el.textContent;
          if (!tc || tc.length > maxLen * 4) continue;
          var t = clean(el.innerText);
          if (!t || t.length > maxLen) continue;
          var dup = false;
          for (var c = el.firstElementChild; c; c = c.nextElementSibling) {
            if (clean(c.innerText) === t) { dup = true; break; }
          }
          if (dup) continue;
          if (!visible(el)) continue;
          for (var r = 0; r < res.length; r++) {
            if (res[r].test(t)) {
              if (r < bestRank || (r === bestRank && preferLast)) { best = el; bestRank = r; bestText = t; }
              break;
            }
          }
        }
        if (!best) return JSON.stringify({ clicked: false });
        var target = best.closest('button, a, [role="button"]') || best;
        var cls = (typeof target.className === 'string') ? target.className : '';
        if (target.disabled || target.getAttribute('aria-disabled') === 'true' || /disable/i.test(cls)) {
          return JSON.stringify({ clicked: false, disabled: true, text: bestText });
        }
        try { target.scrollIntoView({ block: 'center' }); } catch (e) {}
        var rect = target.getBoundingClientRect();
        var x = rect.left + rect.width / 2, y = rect.top + rect.height / 2;
        if (mode === 1) {
          try {
            var touch = new Touch({ identifier: Date.now(), target: target, clientX: x, clientY: y });
            target.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, cancelable: true, touches: [touch], targetTouches: [touch], changedTouches: [touch] }));
            target.dispatchEvent(new TouchEvent('touchend', { bubbles: true, cancelable: true, touches: [], targetTouches: [], changedTouches: [touch] }));
          } catch (e) {}
          var ev = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
          target.dispatchEvent(new MouseEvent('mousedown', ev));
          target.dispatchEvent(new MouseEvent('mouseup', ev));
          target.dispatchEvent(new MouseEvent('click', ev));
        } else {
          target.click();
        }
        return JSON.stringify({ clicked: true, text: bestText });
      } catch (e) {
        return JSON.stringify({ clicked: false, error: String(e) });
      }
    }
    """#
}

/// Turns "S$1,234.50", "RM89.90" or "Rp1.234.567" into a number.
enum PriceParser {
    static func parse(_ text: String?) -> Double? {
        guard let text = text,
              let range = text.range(of: #"\d[\d.,]*"#, options: .regularExpression) else { return nil }
        var num = String(text[range])
        while let last = num.last, last == "." || last == "," { num.removeLast() }
        let separators = num.indices.filter { num[$0] == "." || num[$0] == "," }
        var decimalIndex: String.Index?
        if let last = separators.last {
            let digitsAfter = num.distance(from: last, to: num.endIndex) - 1
            if digitsAfter == 1 || digitsAfter == 2 { decimalIndex = last }
        }
        var out = ""
        for i in num.indices {
            let ch = num[i]
            if ch.isNumber {
                out.append(ch)
            } else if i == decimalIndex {
                out.append(".")
            }
        }
        return Double(out)
    }
}
