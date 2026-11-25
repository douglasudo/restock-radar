import XCTest

/// Drives the real Lazada app on your iPhone: keeps refreshing the product,
/// and the moment it's in stock goes Buy Now → Place Order → Pay.
/// Run from Xcode on a Mac: scheme "LazadaBot", your iPhone, Product ▸ Test (⌘U).
final class LazadaBotTests: XCTestCase {

    private let lazada = XCUIApplication(bundleIdentifier: "com.LazadaSEA.Lazada")

    private struct Node {
        let label: String
        let frame: CGRect
        let type: XCUIElement.ElementType
        let enabled: Bool
    }

    private enum StockState { case inStock, outOfStock, unknown }

    private enum Pattern {
        static let buyNow = "^buy now$"
        static let confirm = "^(confirm|ok|buy now)$"
        static let outOfStock = "^(out of stock|sold out|notify me|set reminder|find similar products|this item just sold out|item chosen is out of stock|no longer available|currently unavailable)"
        static let placeOrder = "^(place order|proceed to pay|place your order)"
        static let pay = "^(pay now|confirm order|confirm payment|pay)$"
        static let needsYou = "(enter (your )?pin|\\botp\\b|\\bcvv\\b|verification code|one-time password|slide to verify|please slide|^log ?in$|^sign ?in$)"
        static let success = "(thank you for|payment success|order placed|order successful|placed successfully)"
        static let total = "^(total|grand total|order total|total payment)"
        static let money = "(S\\$|RM|₱|฿|Rp|₫|\\$)\\s?\\d[\\d.,]*"
        static let popupClose = "^(close|not now|later|skip|got it|no thanks|maybe later)$"
    }

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Main loop

    func testWatchAndBuy() throws {
        guard let url = URL(string: BotConfig.productLink), !BotConfig.productLink.contains("PASTE-YOUR") else {
            XCTFail("Put your product link in BotConfig.swift first.")
            return
        }
        log("Starting in \(BotConfig.placeRealOrder ? "LIVE mode (will place a real order)" : "TEST mode (stops before Place Order)")")
        lazada.activate()

        var nodes = openProduct(url)
        var refreshes = 0
        let started = Date()

        while Date().timeIntervalSince(started) < BotConfig.maxRunHours * 3600 {
            switch stockState(nodes) {
            case .inStock:
                log("🔥 IN STOCK after \(refreshes) refreshes — buying")
                buy()
                return
            case .outOfStock:
                if refreshes % 20 == 0 { log("Out of stock (refresh #\(refreshes))") }
            case .unknown:
                closePopupIfAny(nodes)
            }

            Thread.sleep(forTimeInterval: BotConfig.refreshEverySeconds)
            refreshes += 1

            // Opening the link again stacks pages inside Lazada, so restart it now and then.
            if refreshes % 25 == 0 {
                lazada.terminate()
                lazada.activate()
            }
            nodes = openProduct(url)
        }
        XCTFail("Stopped after \(BotConfig.maxRunHours) hours with no restock.")
    }

    // MARK: - Buying

    private func buy() {
        let deadline = Date().addingTimeInterval(120)
        var priceChecked = false
        var optionDone = BotConfig.option.trimmingCharacters(in: .whitespaces).isEmpty
        var taps: [String: Int] = [:]
        func bump(_ key: String) -> Int { let n = (taps[key] ?? 0) + 1; taps[key] = n; return n }

        while Date() < deadline {
            let nodes = readScreen()

            if let done = last(nodes, Pattern.success) {
                log("✅ ORDER PLACED — \(done.label)")
                return
            }
            if let blocker = last(nodes, Pattern.needsYou) {
                handOver("Lazada is asking for “\(blocker.label)”. Finish it on the phone NOW.")
                return
            }

            // Checkout page
            if let place = last(nodes, Pattern.placeOrder) {
                if let total = checkoutTotal(nodes) {
                    log("Checkout total: \(total)")
                    if total > BotConfig.maxPrice + 0.001 {
                        XCTFail("Total \(total) is above your max \(BotConfig.maxPrice). Nothing was bought.")
                        return
                    }
                }
                if !BotConfig.placeRealOrder {
                    log("🧪 TEST worked: reached checkout. Set placeRealOrder = true in BotConfig.swift to buy for real.")
                    return
                }
                if (taps["place"] ?? 0) >= 3 { handOver("Couldn't press Place Order. Tap it yourself NOW."); return }
                tap(place)
                _ = bump("place")
                log("Pressed \(place.label)")
                Thread.sleep(forTimeInterval: 2.5)
                continue
            }

            // Payment page (after Place Order)
            if (taps["place"] ?? 0) > 0, let pay = last(nodes, Pattern.pay) {
                if (taps["pay"] ?? 0) >= 3 { handOver("Couldn't press Pay. Tap it yourself NOW."); return }
                tap(pay)
                _ = bump("pay")
                log("Pressed \(pay.label)")
                Thread.sleep(forTimeInterval: 2.5)
                continue
            }

            // Product page / options sheet
            if !priceChecked, let price = productPrice(nodes) {
                priceChecked = true
                log("Price on page: \(price)")
                if price > BotConfig.maxPrice + 0.001 {
                    XCTFail("Price \(price) is above your max \(BotConfig.maxPrice). Nothing was bought.")
                    return
                }
            }

            if !optionDone {
                if let opt = findOption(nodes) {
                    tap(opt)
                    optionDone = true
                    log("Picked option “\(opt.label)”")
                    Thread.sleep(forTimeInterval: 0.8)
                    continue
                }
                if (taps["buy"] ?? 0) == 0, let b = last(nodes, Pattern.buyNow) {
                    tap(b)                          // opens the options sheet
                    _ = bump("buy")
                    Thread.sleep(forTimeInterval: 1.2)
                    continue
                }
                if bump("optionMiss") > 8 {
                    XCTFail("Couldn't find the option “\(BotConfig.option)”. Nothing was bought.")
                    return
                }
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }

            if let c = last(nodes, Pattern.confirm) {
                if (taps["buy"] ?? 0) >= 5 { handOver("Stuck after Buy Now. Tap through yourself NOW."); return }
                tap(c)
                _ = bump("buy")
                log("Pressed \(c.label)")
                Thread.sleep(forTimeInterval: 1.5)
                continue
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        handOver("Buying took too long. Finish on the phone NOW.")
    }

    private func handOver(_ message: String) {
        log("✋ " + message)
        XCTFail(message)   // shows red in Xcode (turn on a sound for this in Xcode ▸ Settings ▸ Behaviors)
    }

    // MARK: - Reading the Lazada screen

    private func openProduct(_ url: URL) -> [Node] {
        XCUIDevice.shared.system.open(url)
        _ = lazada.wait(for: .runningForeground, timeout: 8)
        let deadline = Date().addingTimeInterval(8)
        var nodes: [Node] = []
        while Date() < deadline {
            nodes = readScreen()
            if stockState(nodes) != .unknown { return nodes }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return nodes
    }

    /// One fast read of everything on screen (labels and positions).
    private func readScreen() -> [Node] {
        guard let snapshot = try? lazada.snapshot() else { return [] }
        let screen = lazada.frame
        var out: [Node] = []
        func walk(_ s: XCUIElementSnapshot) {
            var text = s.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty, let v = s.value as? String { text = v.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !text.isEmpty, s.frame.width > 1, s.frame.height > 1, screen.intersects(s.frame) {
                out.append(Node(label: text, frame: s.frame, type: s.elementType, enabled: s.isEnabled))
            }
            for child in s.children { walk(child) }
        }
        walk(snapshot)
        return out
    }

    private func stockState(_ nodes: [Node]) -> StockState {
        if first(nodes, Pattern.outOfStock) != nil { return .outOfStock }
        if let b = last(nodes, Pattern.buyNow), b.enabled { return .inStock }
        return .unknown
    }

    private func closePopupIfAny(_ nodes: [Node]) {
        if let close = last(nodes, Pattern.popupClose) {
            tap(close)
            log("Closed a pop-up (\(close.label))")
        }
    }

    private func findOption(_ nodes: [Node]) -> Node? {
        let want = BotConfig.option.trimmingCharacters(in: .whitespaces)
        if let exact = nodes.last(where: { $0.label.caseInsensitiveCompare(want) == .orderedSame }) { return exact }
        return nodes.last(where: { $0.label.count <= want.count + 20 && $0.label.localizedCaseInsensitiveContains(want) })
    }

    private func productPrice(_ nodes: [Node]) -> Double? {
        for n in nodes where n.label.count < 30 {
            if let r = n.label.range(of: Pattern.money, options: .regularExpression) {
                return parsePrice(String(n.label[r]))
            }
        }
        return nil
    }

    private func checkoutTotal(_ nodes: [Node]) -> Double? {
        guard let idx = nodes.lastIndex(where: { matches($0.label, Pattern.total) }) else { return nil }
        for n in nodes[idx...].prefix(4) {
            if let r = n.label.range(of: Pattern.money, options: .regularExpression) {
                return parsePrice(String(n.label[r]))
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func first(_ nodes: [Node], _ pattern: String) -> Node? {
        nodes.first { matches($0.label, pattern) }
    }

    /// Last match = the one drawn on top (pop-up sheets come later in the tree).
    private func last(_ nodes: [Node], _ pattern: String) -> Node? {
        nodes.last { matches($0.label, pattern) }
    }

    private func tap(_ node: Node) {
        let origin = lazada.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        origin.withOffset(CGVector(dx: node.frame.midX, dy: node.frame.midY)).tap()
    }

    private func parsePrice(_ text: String) -> Double? {
        guard let r = text.range(of: "\\d[\\d.,]*", options: .regularExpression) else { return nil }
        var num = String(text[r])
        while let l = num.last, l == "." || l == "," { num.removeLast() }
        let seps = num.indices.filter { num[$0] == "." || num[$0] == "," }
        var decimal: String.Index?
        if let lastSep = seps.last {
            let after = num.distance(from: lastSep, to: num.endIndex) - 1
            if after == 1 || after == 2 { decimal = lastSep }
        }
        var out = ""
        for i in num.indices {
            if num[i].isNumber { out.append(num[i]) } else if i == decimal { out.append(".") }
        }
        return Double(out)
    }

    private func log(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[LazadaBot \(time)] \(message)")
    }
}
