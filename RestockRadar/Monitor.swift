import Foundation
import UIKit
import WebKit
import AudioToolbox

/// The engine: loads each watched page in a real (hidden) browser, reads it,
/// raises the alarm when something comes back in stock, and, for items armed
/// with auto-buy, goes straight through checkout.
@MainActor
final class Monitor: NSObject, ObservableObject, WKNavigationDelegate {

    struct BuyProgress {
        let itemID: UUID
        let name: String
        let isLive: Bool
        var lines: [String]
    }

    enum BuyOutcome {
        case ordered
        case testStop(String)
        case needsYou(String)
        case failed(String)
    }

    @Published private(set) var isRunning = false
    @Published private(set) var currentItemID: UUID?
    @Published private(set) var statusLine = "Not watching yet"
    @Published private(set) var nextDue: [UUID: Date] = [:]
    @Published private(set) var needsVerification = false
    @Published private(set) var browserOpen = false
    @Published private(set) var alarm: AlarmInfo?
    @Published private(set) var lastSignals: [UUID: PageSignals] = [:]
    @Published private(set) var buying: BuyProgress?
    @Published private(set) var verifyProgress: String?   // "Checking links 12/90"
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?
    private var nextScan: Date = .distantPast
    private var verifyCancelled = false

    let webView: WKWebView

    private var store: ItemStore?
    private let alarmPlayer = AlarmPlayer()
    private var loopTask: Task<Void, Never>?
    private var navContinuation: CheckedContinuation<Bool, Never>?
    private var navToken = UUID()
    private var isChecking = false
    private var abortCheck = false
    private var buyCancelled = false
    private var verificationNotified = false
    private var lastJump: Date?

    /// True for a few seconds after we opened the Lazada app ourselves.
    var recentlyJumped: Bool {
        guard let t = lastJump else { return false }
        return Date().timeIntervalSince(t) < 20
    }

    /// "lazadaApp" = open the product in the Lazada app; "autoBuy" = buy inside Restock Radar.
    static var buyMode: String {
        UserDefaults.standard.string(forKey: "buyMode") ?? "lazadaApp"
    }

    static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // keeps your Lazada login between checks
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        applyUserAgent()
    }

    func attach(_ store: ItemStore) {
        self.store = store
    }

    func applyUserAgent() {
        let desktop = UserDefaults.standard.object(forKey: "desktopMode") as? Bool ?? false
        webView.customUserAgent = desktop ? Self.desktopUA : Self.mobileUA
    }

    private var isTestMode: Bool {
        UserDefaults.standard.object(forKey: "testMode") as? Bool ?? true
    }

    // MARK: - Timing

    /// Random wait before an item's next refresh: anywhere in your chosen range,
    /// plus now and then a longer pause, so the pattern isn't a fixed beat.
    static func randomDelay() -> Double {
        let d = UserDefaults.standard
        let lo = max(5, d.object(forKey: "minInterval") as? Double ?? 20)
        let hi = max(lo + 1, d.object(forKey: "maxInterval") as? Double ?? 50)
        var delay = Double.random(in: lo...hi)
        let breaks = d.object(forKey: "takeBreaks") as? Bool ?? true
        if breaks && Double.random(in: 0..<1) < 0.08 {
            delay += Double.random(in: 30...90)
        }
        return delay
    }

    // MARK: - Start / stop

    func start() {
        guard !isRunning, verifyProgress == nil else { return }
        isRunning = true
        needsVerification = false
        verificationNotified = false
        statusLine = "Starting…"
        nextScan = Date()   // look for new official listings first
        // First checks go out a few random seconds apart, in random order.
        // A ticked product that's already in stock counts as "back" on its first check.
        var offset = 0.0
        for item in activeItems().shuffled() {
            store?.mutate(item.id) { $0.lastDefiniteStatus = .unknown }
            nextDue[item.id] = Date().addingTimeInterval(offset)
            offset += Double.random(in: 2...6)
        }
        updateIdleTimer()
        loopTask = Task { @MainActor [weak self] in
            while true {
                guard let self = self, self.isRunning, !Task.isCancelled else { return }
                await self.tick()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        isRunning = false
        loopTask?.cancel()
        loopTask = nil
        abortCheck = true
        buyCancelled = true
        finishNavigation(false)
        statusLine = "Stopped"
        updateIdleTimer()
    }

    func updateIdleTimer() {
        let keepAwake = UserDefaults.standard.object(forKey: "keepAwake") as? Bool ?? true
        UIApplication.shared.isIdleTimerDisabled = (isRunning || buying != nil) && keepAwake
    }

    /// Check one item as soon as possible.
    func checkNow(_ id: UUID) {
        guard buying == nil else { return }
        nextDue[id] = .distantPast
        guard !isRunning else { return }   // the running loop will pick it up within a second
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            while self.isChecking { try? await Task.sleep(nanoseconds: 300_000_000) }
            await self.check(itemID: id)
        }
    }

    // MARK: - Link check (one pass over every product)

    /// Opens every product once, slowly and in random order, to confirm the link works.
    func verifyAllLinks() {
        guard verifyProgress == nil, buying == nil, !isRunning, let store = store else { return }
        verifyCancelled = false
        let ids = store.items.map { $0.id }.shuffled()
        verifyProgress = "Checking links 0/\(ids.count)"
        updateIdleTimerForVerify(true)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var done = 0
            for id in ids {
                if self.verifyCancelled { break }
                while self.isChecking || self.needsVerification || self.browserOpen {
                    if self.verifyCancelled { break }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                if self.verifyCancelled { break }
                await self.check(itemID: id)
                done += 1
                self.verifyProgress = "Checking links \(done)/\(ids.count)"
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 3...8) * 1_000_000_000))
            }
            let items = self.store?.items ?? []
            let broken = items.filter { $0.linkStatus == "broken" }.count
            let ok = items.filter { $0.linkStatus == "ok" }.count
            self.verifyProgress = nil
            self.statusLine = self.verifyCancelled
                ? "Link check stopped. \(ok) working, \(broken) broken so far."
                : "Link check done: \(ok) working, \(broken) broken, \(items.count - ok - broken) unclear."
            self.updateIdleTimerForVerify(false)
        }
    }

    func cancelVerify() {
        verifyCancelled = true
    }

    private func updateIdleTimerForVerify(_ on: Bool) {
        let keepAwake = UserDefaults.standard.object(forKey: "keepAwake") as? Bool ?? true
        UIApplication.shared.isIdleTimerDisabled = keepAwake && (on || isRunning || buying != nil)
    }

    // MARK: - Browser panel

    func openBrowser() {
        browserOpen = true
    }

    func showInBrowser(_ url: URL) {
        browserOpen = true
        guard buying == nil else { return }
        if isChecking {
            abortCheck = true
            finishNavigation(false)
        }
        webView.load(URLRequest(url: url))
    }

    func openLogin(for items: [WatchItem]) {
        let host = items.compactMap { $0.url?.host?.lowercased() }.first { $0.contains("lazada.") } ?? "www.lazada.sg"
        let suffix = host.components(separatedBy: "lazada.").last ?? "sg"
        if let url = URL(string: "https://member.lazada.\(suffix)/user/login") {
            showInBrowser(url)
        }
    }

    func closeBrowser() {
        browserOpen = false
    }

    func resumeAfterVerification() {
        needsVerification = false
        verificationNotified = false
        browserOpen = false
    }

    // MARK: - Alarm

    func dismissAlarm() {
        alarmPlayer.stop()
        if let kind = alarm?.kind, kind == .ordered || kind == .testRun || kind == .failed {
            browserOpen = false
        }
        alarm = nil
    }

    func openAlarmItem() {
        lastJump = Date()
        if let url = alarm?.url {
            UIApplication.shared.open(url)   // opens the Lazada app if installed
        }
        dismissAlarm()
    }

    // MARK: - Loop

    private func tick() async {
        if buying != nil {
            statusLine = "Auto-buying…"
            return
        }
        if needsVerification {
            statusLine = "Paused: Lazada wants you to verify"
            return
        }
        if browserOpen {
            statusLine = "Paused while the browser is open"
            return
        }
        let autoScan = UserDefaults.standard.object(forKey: "autoScan") as? Bool ?? true
        if autoScan && !isScanning && Date() >= nextScan {
            await scanOfficialStore(manual: false)
            return
        }
        guard let item = nextDueItem() else {
            statusLine = idleStatus()
            return
        }
        await check(itemID: item.id)
    }

    // MARK: - Scan the official store for new card products

    private struct DiscoveryResult: Decodable {
        struct Entry: Decodable { let id: String; let title: String; let price: String }
        var blocked: Bool
        var noResult: Bool
        var items: [Entry]
    }

    /// Reads the product cards on the official store's search page (desktop layout).
    static let discoveryScript = #"""
    (function () {
      try {
        var cards = Array.prototype.slice.call(document.querySelectorAll('[data-qa-locator="product-item"]'));
        var items = [];
        cards.forEach(function (c) {
          var a = c.querySelector('a[href*="/products/"]');
          var m = a && a.href.match(/-i(\d+)/);
          if (!m) return;
          var lines = c.innerText.split('\n').map(function (s) { return s.trim(); }).filter(Boolean);
          var price = '';
          for (var i = 0; i < lines.length; i++) { if (/^\$/.test(lines[i])) { price = lines[i]; break; } }
          items.push({ id: m[1], title: ((a && a.title) || lines[0] || '').trim(), price: price });
        });
        return JSON.stringify({
          blocked: /punish|_____tmd/.test(location.href),
          noResult: /No Result|cannot find any matches/i.test(document.body ? document.body.innerText : ''),
          items: items
        });
      } catch (e) {
        return JSON.stringify({ blocked: false, noResult: false, items: [] });
      }
    })();
    """#

    func scanNow() {
        guard !isScanning, buying == nil, verifyProgress == nil else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            while self.isChecking { try? await Task.sleep(nanoseconds: 300_000_000) }
            await self.scanOfficialStore(manual: true)
        }
    }

    private func scanOfficialStore(manual: Bool) async {
        guard let store = store, !isScanning else { return }
        isScanning = true
        statusLine = "Scanning the official Pokémon store for new card products…"
        let savedUA = webView.customUserAgent
        webView.customUserAgent = Self.desktopUA      // the store's listing is read from the desktop layout
        var found: [(id: String, title: String, price: String)] = []
        var blocked = false
        var softBlocked = false

        for page in 1...5 {
            let ok = await load(URLRequest(url: Catalog.storeSearchURL(page: page),
                                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30))
            if !ok { break }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let json = await runJS(Self.discoveryScript), let data = json.data(using: .utf8),
                  let res = try? JSONDecoder().decode(DiscoveryResult.self, from: data) else { break }
            if res.blocked { blocked = true; break }
            if res.items.isEmpty {
                if page == 1 { softBlocked = true }   // the store always has card products, so empty = Lazada holding back
                break
            }
            found += res.items.map { (id: $0.id, title: $0.title, price: $0.price) }
            if res.items.count < 40 { break }
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 2...5) * 1_000_000_000))
        }

        webView.customUserAgent = savedUA
        isScanning = false

        if blocked {
            needsVerification = true
            statusLine = "Lazada wants a slider check before scanning the store."
            nextScan = Date().addingTimeInterval(Double.random(in: 600...1200))
            return
        }
        if softBlocked {
            statusLine = "Store scan got no results (Lazada busy). Trying again later."
            nextScan = Date().addingTimeInterval(Double.random(in: 600...1200))
            return
        }

        lastScan = Date()
        nextScan = Date().addingTimeInterval(Double.random(in: 1500...2700))   // every 25–45 min, random
        let added = store.mergeDiscovered(found)
        if added.isEmpty {
            statusLine = "Scanned \(found.count) official listings: nothing new."
            return
        }
        statusLine = "Found \(added.count) new official card product\(added.count == 1 ? "" : "s")!"
        for item in added where item.isEnabled { nextDue[item.id] = Date() }   // check new ticked ones right away
        if added.count <= 3 {
            for item in added {
                Notifier.send(title: "New on the official Pokémon store",
                              body: item.displayName + (item.isEnabled ? " (matches your keywords, checking now)" : ""),
                              url: item.url)
            }
        } else {
            Notifier.send(title: "\(added.count) new products on the official Pokémon store",
                          body: "\(added.filter { $0.isEnabled }.count) match your keywords and were ticked.", url: nil)
        }
    }

    private func activeItems() -> [WatchItem] {
        (store?.items ?? []).filter { $0.isEnabled && $0.url != nil }
    }

    private func nextDueItem() -> WatchItem? {
        let now = Date()
        var best: (item: WatchItem, due: Date)?
        for item in activeItems() {
            let due = nextDue[item.id] ?? .distantPast
            guard due <= now else { continue }
            if best == nil || due < best!.due { best = (item, due) }
        }
        return best?.item
    }

    private func idleStatus() -> String {
        let active = activeItems()
        if active.isEmpty { return "No products ticked. Tick some, then Start." }
        let plural = active.count == 1 ? "" : "s"
        if let soonest = active.compactMap({ nextDue[$0.id] }).min() {
            let secs = max(0, Int(soonest.timeIntervalSinceNow.rounded()))
            return "Watching \(active.count) item\(plural) · next check in \(secs)s"
        }
        return "Watching \(active.count) item\(plural)"
    }

    // MARK: - One check

    private func check(itemID: UUID) async {
        guard !isChecking, buying == nil, let item = store?.item(id: itemID), let url = item.url else { return }
        isChecking = true
        abortCheck = false
        currentItemID = itemID
        statusLine = "Checking \(item.displayName)…"

        let result = await loadAndDetect(url: url, item: item)

        isChecking = false
        currentItemID = nil
        nextDue[itemID] = Date().addingTimeInterval(Self.randomDelay())
        if !isRunning {
            statusLine = "Not watching. Tap Start to keep checking."
        }
        guard let result = result else { return }
        apply(result, to: itemID)
    }

    private func loadAndDetect(url: URL, item: WatchItem) async -> DetectionResult? {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        let loaded = await load(request)
        if abortCheck || Task.isCancelled { return nil }
        if !loaded {
            return DetectionResult(status: .error, price: nil, title: nil,
                                   note: "Page didn't load. Check your internet connection.")
        }

        // Lazada builds the page with JavaScript after it "finishes", so look a few times.
        var latest: DetectionResult?
        for attempt in 0..<6 {
            try? await Task.sleep(nanoseconds: attempt == 0 ? 2_000_000_000 : 1_500_000_000)
            if abortCheck || Task.isCancelled { return nil }
            guard let signals = await readSignals() else { continue }
            var stored = signals
            stored.text = nil
            lastSignals[item.id] = stored
            let r = Detector.decide(signals, item: item)
            latest = r
            if r.status != .unknown { return r }
        }
        return latest ?? DetectionResult(status: .error, price: nil, title: nil, note: "Couldn't read the page")
    }

    private func apply(_ r: DetectionResult, to id: UUID) {
        guard let store = store, var item = store.item(id: id) else { return }
        let previousDefinite = item.lastDefiniteStatus
        let previousPrice = item.price

        item.status = r.status
        item.lastChecked = Date()
        item.lastNote = r.note
        item.checkCount += 1
        if let p = r.price { item.price = p }
        if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let t = r.title {
            item.name = t
        }
        if r.status == .inStock || r.status == .outOfStock {
            item.lastDefiniteStatus = r.status
            item.linkStatus = "ok"
        } else if r.status == .error && r.note.hasPrefix("Broken link") {
            item.linkStatus = "broken"
        } else if r.status == .unknown && r.title != nil && item.linkStatus.isEmpty {
            item.linkStatus = "ok"      // a real product page loaded, stock just unclear
        }
        item.history.insert(CheckRecord(date: Date(), status: r.status, price: r.price, note: r.note), at: 0)
        if item.history.count > 30 { item.history.removeLast(item.history.count - 30) }
        store.update(item)

        // Alerts and buying only for ticked products, never during the link check,
        // and (by default) only when the seller is the official Pokémon store.
        let officialOnly = UserDefaults.standard.object(forKey: "officialOnly") as? Bool ?? true
        let sellerOK = !officialOnly || item.official || r.officialSeller
        let canAct = item.isEnabled && verifyProgress == nil && sellerOK
        if r.status == .inStock && item.isEnabled && !sellerOK {
            store.mutate(id) { $0.lastNote = "In stock, but NOT sold by the official Pokémon Store, so skipped." }
        }

        switch r.status {
        case .inStock where previousDefinite != .inStock && canAct:
            if Self.buyMode == "lazadaApp" {
                jumpToLazadaApp(item)
            } else if item.autoBuy && item.boughtAt == nil && item.maxPrice != nil {
                startBuy(itemID: item.id, reload: false)   // we're already on the product page
            } else {
                raiseAlarm(for: item)
            }
        case .blocked:
            needsVerification = true
            nextDue[id] = Date()
            if !verificationNotified {
                verificationNotified = true
                Notifier.send(title: "Lazada wants a quick check",
                              body: "Watching is paused. Open Restock Radar, slide the check, then tap Resume.",
                              url: nil)
            }
        default:
            break
        }

        if canAct, item.alertOnPriceChange, let new = r.price, let old = previousPrice, new != old {
            Notifier.send(title: "Price change: \(item.displayName)", body: "\(old) → \(new)", url: item.url)
        }
    }

    private func raiseAlarm(for item: WatchItem, loud: Bool = true) {
        guard let url = item.url else { return }
        let body = [item.price, "Tap to open in Lazada"].compactMap { $0 }.joined(separator: " · ")
        Notifier.send(title: "🔥 IN STOCK: \(item.displayName)", body: body, url: url)
        alarm = AlarmInfo(kind: .inStock, itemID: item.id, name: item.displayName, url: url,
                          price: item.price, message: loud ? nil : "Opened in the Lazada app. Tap Buy Now → Place Order there.")
        if loud {
            alarmPlayer.start()
        } else {
            AudioServicesPlayAlertSound(SystemSoundID(1005))
        }
    }

    /// Opens the product straight in the Lazada app the moment it's back.
    private func jumpToLazadaApp(_ item: WatchItem) {
        guard let original = item.url else { return }
        // Prefer the full product address the page ended up on (short s.lazada.sg links may not open the app).
        var target = original
        if let s = lastSignals[item.id]?.url, let resolved = URL(string: s),
           resolved.host?.contains("lazada.") == true {
            target = resolved
        }
        store?.mutate(item.id) { $0.isEnabled = false }   // untick so it doesn't keep jumping
        lastJump = Date()
        raiseAlarm(for: item, loud: false)
        let link = target
        UIApplication.shared.open(link, options: [.universalLinksOnly: true]) { opened in
            if !opened {
                UIApplication.shared.open(link)   // not an app link: open normally
            }
        }
    }

    /// "I bought it" from the alert: move to the Bought list.
    func markBought(_ id: UUID) {
        store?.recordPurchase(of: id)
        nextDue[id] = nil
        dismissAlarm()
    }

    // MARK: - Auto-buy

    /// Runs the buy flow for one item. `reload` loads the product page first
    /// (used for the manual "Run auto-buy now" button).
    func startBuy(itemID: UUID, reload: Bool) {
        guard buying == nil, let item = store?.item(id: itemID) else { return }
        let live = !isTestMode
        buyCancelled = false
        buying = BuyProgress(itemID: itemID, name: item.displayName, isLive: live, lines: [])
        browserOpen = true
        updateIdleTimer()
        Notifier.send(title: "🔥 IN STOCK: \(item.displayName)",
                      body: live ? "Auto-buying now…" : "Test run: heading to checkout (no order will be placed).",
                      url: item.url)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            while self.isChecking { try? await Task.sleep(nanoseconds: 200_000_000) }
            let outcome = await self.runBuy(item: item, live: live, reload: reload)
            self.finishBuy(item: item, outcome: outcome)
        }
    }

    func cancelBuy() {
        buyCancelled = true
    }

    private func buyLog(_ line: String) {
        guard buying != nil else { return }
        buying?.lines.append(line)
        if let count = buying?.lines.count, count > 8 { buying?.lines.removeFirst(count - 8) }
        statusLine = line
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func runBuy(item: WatchItem, live: Bool, reload: Bool) async -> BuyOutcome {
        guard let url = item.url else { return .failed("This item has no valid link.") }
        guard let maxPrice = item.maxPrice else { return .failed("Set a max price for this item first.") }

        buyLog(live ? "LIVE auto-buy started" : "TEST run started (won't place an order)")
        if reload {
            buyLog("Opening the product page")
            let ok = await load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30))
            if !ok { return .failed("The product page didn't load.") }
            await pause(1.5)
        }

        let variant = item.variantText.trimmingCharacters(in: .whitespacesAndNewlines)
        var variantDone = variant.isEmpty
        var priceChecked = false
        var counts: [String: Int] = [:]
        var verifyNoticed = false
        let deadline = Date().addingTimeInterval(180)

        func bump(_ key: String) -> Int {
            let n = (counts[key] ?? 0) + 1
            counts[key] = n
            return n
        }

        while Date() < deadline {
            if buyCancelled { return .failed("Stopped.") }
            guard let snap = await readBuySnapshot() else {
                await pause(0.6)
                continue
            }

            switch snap.stage {
            case "success":
                return .ordered

            case "login":
                return .needsYou("Lazada wants you to log in. Log in on this screen now, then buy by hand (or run auto-buy again).")

            case "verify":
                if !verifyNoticed {
                    verifyNoticed = true
                    buyLog("Lazada wants a slider check. Do it on screen now!")
                    AudioServicesPlayAlertSound(SystemSoundID(1005))
                    Notifier.send(title: "Slide Lazada's check now!", body: "Auto-buy is waiting for you.", url: nil)
                }
                await pause(1.0)

            case "needsInput":
                return .needsYou("Lazada needs you to finish payment (a code, CVV or PIN). Do it on this screen now.")

            case "payment":
                if !live { return .testStop("Reached the payment page.") }
                if (counts["pay"] ?? 0) >= 3 {
                    return .needsYou("Couldn't press the final Pay button. Tap it yourself now.")
                }
                if await click(BuyScript.payPatterns, preferLast: true, attempt: counts["pay"] ?? 0) {
                    _ = bump("pay")
                    buyLog("Pressed Pay")
                    await pause(4)
                } else {
                    if bump("payWait") > 12 { return .needsYou("Couldn't find the Pay button. Finish on this screen now.") }
                    await pause(0.8)
                }

            case "checkout":
                if snap.calculating == true {          // "Place Order  Calculating…"
                    await pause(0.3)
                    continue
                }
                if let total = PriceParser.parse(snap.total), total > maxPrice + 0.001 {
                    return .failed("Checkout total \(snap.total ?? "") is above your max of \(item.maxPriceText). Nothing was bought.")
                }
                if !live {
                    let totalText = (snap.total?.isEmpty == false) ? " Total: \(snap.total!)." : ""
                    return .testStop("Reached checkout.\(totalText) Stopped before Place Order.")
                }
                if (counts["place"] ?? 0) >= 3 {
                    return .needsYou("Couldn't press Place Order. Tap it yourself now.")
                }
                if await click(BuyScript.placeOrderPatterns, preferLast: true, attempt: counts["place"] ?? 0) {
                    _ = bump("place")
                    buyLog("Pressed Place Order")
                    await pause(4)
                } else {
                    if bump("placeWait") > 12 { return .needsYou("Couldn't find Place Order. Finish on this screen now.") }
                    await pause(0.8)
                }

            case "product":
                if snap.soldOut == true && (counts["buy"] ?? 0) == 0 {
                    return .failed("It sold out again before the app could press Buy Now. Still watching the rest.")
                }
                if !priceChecked, let price = PriceParser.parse(snap.price) {
                    priceChecked = true
                    if price > maxPrice + 0.001 {
                        return .failed("Price \(snap.price ?? "") is above your max of \(item.maxPriceText). Nothing was bought.")
                    }
                    buyLog("Price \(snap.price ?? "") is within your max")
                }

                if !variantDone {
                    if await click(BuyScript.variantPatterns(variant), preferLast: false,
                                   attempt: counts["variant"] ?? 0, maxLength: 80) {
                        variantDone = true
                        buyLog("Picked option “\(variant)”")
                        await pause(1.0)
                        continue
                    }
                    // On the mobile site the options only appear after the first Buy Now tap.
                    if (counts["buy"] ?? 0) == 0 {
                        if await click(BuyScript.buyPatterns.filter { $0 == "^buy now$" }, preferLast: false, attempt: 0) {
                            _ = bump("buy")
                            buyLog("Opened the options")
                        }
                    } else if bump("variantMiss") > 8 {
                        return .failed("Couldn't find the option “\(variant)”. Nothing was bought.")
                    }
                    await pause(0.8)
                    continue
                }

                if (counts["buy"] ?? 0) >= 5 {
                    return .needsYou("Couldn't get past Buy Now. Tap it yourself now.")
                }
                if await click(BuyScript.buyPatterns, preferLast: true, attempt: counts["buy"] ?? 0) {
                    _ = bump("buy")
                    buyLog("Pressed Buy Now")
                    await pause(2.0)
                } else {
                    if bump("buyMissing") > 10 {
                        return .failed("No active Buy Now button. It may have sold out again.")
                    }
                    await pause(0.7)
                }

            default:
                await pause(0.8)
            }
        }
        return .needsYou("Auto-buy took too long. Finish on this screen now.")
    }

    private func finishBuy(item: WatchItem, outcome: BuyOutcome) {
        let kind: AlarmInfo.Kind
        let message: String
        switch outcome {
        case .ordered:
            kind = .ordered
            message = "Check Lazada → My Orders to confirm. It's been moved off your list to “Bought”."
            store?.recordPurchase(of: item.id)
            nextDue[item.id] = nil
        case .testStop(let m):
            kind = .testRun
            message = m + " Turn off Test mode in Auto-buy setup to buy for real."
        case .needsYou(let m):
            kind = .needsYou
            message = m
        case .failed(let m):
            kind = .failed
            message = m
        }
        buying = nil
        statusLine = kind.title
        updateIdleTimer()
        Notifier.send(title: "\(kind.title) \(item.displayName)", body: message, url: nil)
        alarm = AlarmInfo(kind: kind, itemID: item.id, name: item.displayName, url: item.url,
                          price: item.price, message: message)
        switch kind {
        case .ordered, .needsYou:
            alarmPlayer.start()
        default:
            AudioServicesPlayAlertSound(SystemSoundID(1005))
        }
    }

    private func readBuySnapshot() async -> BuySnapshot? {
        guard let json = await runJS(BuyScript.snapshot), let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BuySnapshot.self, from: data)
    }

    private func click(_ patterns: [String], preferLast: Bool, attempt: Int, maxLength: Int = 40) async -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: patterns),
              let array = String(data: data, encoding: .utf8) else { return false }
        let mode = attempt % 2   // alternate: normal click, then simulated finger tap
        let js = "(\(BuyScript.clickFunction))(\(array), \(preferLast), \(mode), \(maxLength))"
        guard let json = await runJS(js), let d = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return false }
        return obj["clicked"] as? Bool ?? false
    }

    // MARK: - WebView plumbing

    private func load(_ request: URLRequest) async -> Bool {
        finishNavigation(false)
        let token = UUID()
        navToken = token
        scheduleTimeout(token)
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.navContinuation = cont
            self.webView.load(request)
        }
    }

    private func scheduleTimeout(_ token: UUID) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self = self, self.navToken == token else { return }
            self.finishNavigation(false)
        }
    }

    private func finishNavigation(_ ok: Bool) {
        guard let cont = navContinuation else { return }
        navContinuation = nil
        cont.resume(returning: ok)
    }

    private func runJS(_ script: String) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            self.webView.evaluateJavaScript(script) { result, _ in
                cont.resume(returning: result as? String)
            }
        }
    }

    private func readSignals() async -> PageSignals? {
        guard let json = await runJS(Detector.script), let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PageSignals.self, from: data)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    private func handleNavigationError(_ error: Error) {
        let ns = error as NSError
        // -999 = replaced by another load (redirects); 102 = link handed to another app
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
        finishNavigation(false)
    }
}
