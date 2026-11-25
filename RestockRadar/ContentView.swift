import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: Monitor
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // The real browser always sits underneath, full size, so pages render properly.
            BrowserScreen()

            MainListScreen()
                .opacity(monitor.browserOpen ? 0 : 1)
                .allowsHitTesting(!monitor.browserOpen)

            if let info = monitor.alarm {
                AlarmView(info: info)
                    .zIndex(10)
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background && monitor.isRunning && !monitor.recentlyJumped {
                Notifier.send(title: "Restock Radar is paused",
                              body: "iPhone stops checks while the app is closed. Tap to reopen and keep watching.",
                              url: nil)
            }
        }
    }
}

// MARK: - Main list

struct MainListScreen: View {
    @EnvironmentObject private var store: ItemStore
    @EnvironmentObject private var monitor: Monitor
    @AppStorage("keepAwake") private var keepAwake = true
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var showingKeywords = false

    private var allSelected: Bool {
        !store.items.isEmpty && store.items.allSatisfy { $0.isEnabled }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ControlCard(keepAwake: $keepAwake)
                }

                Section {
                    Button {
                        showingKeywords = true
                    } label: {
                        HStack {
                            Label("What to buy", systemImage: "line.3.horizontal.decrease.circle")
                            Spacer()
                            Text("\(Keywords.selectedKinds.count) types · \(Keywords.selectedSets.count) sets")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    Text("Only products from the official \(Catalog.storeName) on Lazada are listed below.")
                }

                if monitor.needsVerification {
                    Section {
                        VerificationBanner()
                    }
                }

                if store.items.isEmpty {
                    Section {
                        EmptyStateRow { showingAdd = true }
                    }
                }

                ForEach(store.groups, id: \.self) { group in
                    let groupItems = store.items.filter { $0.group == group }
                    let allTicked = groupItems.allSatisfy { $0.isEnabled }
                    Section {
                        ForEach(groupItems) { item in
                            HStack(spacing: 12) {
                                Button {
                                    store.mutate(item.id) { $0.isEnabled.toggle() }
                                } label: {
                                    Image(systemName: item.isEnabled ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundColor(item.isEnabled ? .accentColor : .secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item.isEnabled ? "Ticked" : "Not ticked")

                                NavigationLink(value: item.id) {
                                    ItemRow(item: item)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.delete(id: item.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    monitor.checkNow(item.id)
                                } label: {
                                    Label("Check", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)
                            }
                        }
                    } header: {
                        HStack {
                            Text("\(group.isEmpty ? "My products" : group) · \(groupItems.count)")
                            Spacer()
                            Button(allTicked ? "Untick all" : "Tick all") {
                                store.setGroupSelected(group, !allTicked)
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }

                if !store.items.isEmpty {
                    Section {
                        LinkCheckRow()
                    } footer: {
                        Text("Products are ticked by “What to buy”; you can also tick or untick any one by hand. The list came from the official store on \(Catalog.collectedOn), and the app adds new official listings when it scans. Swipe left on a product to check it now or delete it.")
                    }
                }

                if !store.purchases.isEmpty {
                    Section {
                        ForEach(store.purchases) { p in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                Text(([p.price, p.date.formatted(date: .abbreviated, time: .shortened)] as [String?])
                                        .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.clearPurchase(id: p.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("Bought")
                    }
                }
            }
            .navigationTitle("Restock Radar")
            .navigationDestination(for: UUID.self) { id in
                ItemDetailView(itemID: id)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    Button {
                        monitor.openBrowser()
                    } label: {
                        Image(systemName: "safari")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddItemView()
                    .environmentObject(store)
                    .environmentObject(monitor)
            }
            .sheet(isPresented: $showingKeywords) {
                KeywordsView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingSettings) {
                AutoBuySettingsView()
                    .environmentObject(store)
                    .environmentObject(monitor)
            }
            .onChange(of: keepAwake) { _ in
                monitor.updateIdleTimer()
            }
        }
    }
}

struct ControlCard: View {
    @EnvironmentObject private var store: ItemStore
    @EnvironmentObject private var monitor: Monitor
    @Binding var keepAwake: Bool
    @AppStorage("testMode") private var testMode = true
    @AppStorage("buyMode") private var buyMode = "lazadaApp"
    @AppStorage("minInterval") private var minInterval = 20.0
    @AppStorage("maxInterval") private var maxInterval = 50.0

    private var selected: [WatchItem] { store.items.filter { $0.isEnabled } }
    private var buyCount: Int { selected.filter { $0.autoBuy && $0.maxPrice != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if monitor.isRunning {
                    monitor.stop()
                } else {
                    monitor.start()
                }
            } label: {
                Label(monitor.isRunning ? "Stop" : "Start (\(selected.count) ticked)",
                      systemImage: monitor.isRunning ? "stop.fill" : "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(monitor.isRunning ? .red : .green)
            .disabled(selected.isEmpty && !monitor.isRunning)

            Text(monitor.statusLine)
                .font(.footnote)
                .foregroundColor(.secondary)

            if !selected.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if buyMode == "lazadaApp" {
                        Label("When one's back: opens it in the Lazada app", systemImage: "arrow.up.forward.app")
                    } else {
                        Label("\(buyCount) will auto-buy · \(selected.count - buyCount) alert only",
                              systemImage: "bolt.fill")
                        Label(testMode ? "TEST mode: stops before Place Order" : "LIVE: places real orders",
                              systemImage: testMode ? "checkmark.shield" : "exclamationmark.triangle.fill")
                            .foregroundColor(testMode ? .blue : .red)
                    }
                    Label("Refreshes every \(Int(minInterval))–\(Int(maxInterval))s, random",
                          systemImage: "shuffle")
                }
                .font(.footnote.weight(.semibold))
            }

            Toggle("Keep screen on while running", isOn: $keepAwake)
                .font(.subheadline)

            Text("Leave this app open on screen, plugged in. iPhone pauses apps in the background.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct LinkCheckRow: View {
    @EnvironmentObject private var store: ItemStore
    @EnvironmentObject private var monitor: Monitor

    private var broken: Int { store.items.filter { $0.linkStatus == "broken" }.count }
    private var ok: Int { store.items.filter { $0.linkStatus == "ok" }.count }
    private var missingFromCatalog: Int {
        let have = Set(store.items.compactMap { $0.lazadaItemID })
        return Catalog.items.filter { !have.contains($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let progress = monitor.verifyProgress {
                HStack {
                    ProgressView()
                    Text(progress).font(.subheadline)
                    Spacer()
                    Button("Stop") { monitor.cancelVerify() }
                        .buttonStyle(.bordered)
                }
            } else {
                Button {
                    monitor.verifyAllLinks()
                } label: {
                    Label("Check all links (\(store.items.count))", systemImage: "checkmark.seal")
                }
                .disabled(monitor.isRunning || monitor.buying != nil)
                Text("\(ok) working · \(broken) broken · \(store.items.count - ok - broken) not checked yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if broken > 0 && monitor.verifyProgress == nil {
                Button(role: .destructive) {
                    store.removeBrokenLinks()
                } label: {
                    Label("Remove \(broken) broken link\(broken == 1 ? "" : "s")", systemImage: "trash")
                }
            }
            Divider()
            Button {
                monitor.scanNow()
            } label: {
                Label(monitor.isScanning ? "Scanning official store…" : "Scan official store for new products",
                      systemImage: "magnifyingglass")
            }
            .disabled(monitor.isScanning || monitor.buying != nil || monitor.verifyProgress != nil)
            Text(monitor.lastScan.map { "Last scan \($0.formatted(date: .omitted, time: .shortened)). While running it rescans every 25–45 min." }
                 ?? "While running, the app scans the official store every 25–45 min for new card products.")
                .font(.caption)
                .foregroundColor(.secondary)
            if missingFromCatalog > 0 && monitor.verifyProgress == nil {
                Button {
                    store.importCatalog()
                } label: {
                    Label("Add back \(missingFromCatalog) official product\(missingFromCatalog == 1 ? "" : "s")", systemImage: "plus.circle")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct VerificationBanner: View {
    @EnvironmentObject private var monitor: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Lazada wants to check you're human", systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundColor(.orange)
            Text("Paused. Open the browser, do the slider, then tap Resume.")
                .font(.footnote)
            Button("Open browser") {
                monitor.openBrowser()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(.vertical, 4)
    }
}

struct EmptyStateRow: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No products yet")
                .font(.headline)
            Text("In the Lazada app, open a product, tap Share, then Copy Link. Come back here and tap +.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Add a Lazada product", action: onAdd)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }
}

struct ItemRow: View {
    @EnvironmentObject private var monitor: Monitor
    @AppStorage("buyMode") private var buyMode = "lazadaApp"
    let item: WatchItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.displayName)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                StatusPill(status: item.status, isChecking: monitor.currentItemID == item.id)
            }
            if !item.setName.isEmpty || item.official {
                HStack(spacing: 6) {
                    if item.official {
                        Label("Official", systemImage: "checkmark.shield.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.blue)
                    }
                    if !item.setName.isEmpty {
                        Text(item.setName).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            HStack(spacing: 10) {
                if let price = item.price {
                    Text(price)
                        .font(.subheadline.weight(.semibold))
                }
                if buyMode == "lazadaApp" {
                    Label("Opens Lazada app", systemImage: "arrow.up.forward.app")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                } else if item.autoBuy && item.maxPrice != nil {
                    Label("Buy ≤ \(item.maxPriceText)", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                } else {
                    Text("Alert only")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if item.linkStatus == "broken" {
                    Label("Link broken", systemImage: "link.badge.plus")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.red)
                } else if item.linkStatus == "ok" {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .accessibilityLabel("Link works")
                }
            }
            CountdownText(item: item)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Browser

struct BrowserScreen: View {
    @EnvironmentObject private var monitor: Monitor

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button {
                    monitor.closeBrowser()
                } label: {
                    Label("Back to list", systemImage: "chevron.left")
                }
                Spacer()
                Button {
                    monitor.webView.goBack()
                } label: {
                    Image(systemName: "arrow.backward")
                }
                Button {
                    monitor.webView.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))

            if let buy = monitor.buying {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(buy.isLive ? "Auto-buying (LIVE)" : "Auto-buy test run",
                              systemImage: "bolt.fill")
                            .font(.headline)
                            .foregroundColor(buy.isLive ? .red : .blue)
                        Spacer()
                        Button("Stop") { monitor.cancelBuy() }
                            .buttonStyle(.bordered)
                            .tint(.red)
                    }
                    Text(buy.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    ForEach(Array(buy.lines.suffix(3).enumerated()), id: \.offset) { _, line in
                        Text("• " + line).font(.caption)
                    }
                }
                .padding()
                .background((buy.isLive ? Color.red : Color.blue).opacity(0.12))
            } else if monitor.needsVerification {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Do Lazada's check below (usually a slider). When the product page shows, tap Resume.")
                        .font(.footnote)
                    Button {
                        monitor.resumeAfterVerification()
                    } label: {
                        Text("Resume watching").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding()
                .background(Color.orange.opacity(0.15))
            } else {
                Text(monitor.isRunning ? "Checks are paused while this browser is open." : "This is the browser the app uses to check pages.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            }

            WebViewContainer(webView: monitor.webView)
        }
    }
}

// MARK: - Alarm

struct AlarmView: View {
    @EnvironmentObject private var monitor: Monitor
    let info: AlarmInfo

    private var background: Color {
        switch info.kind {
        case .inStock, .ordered: return .green
        case .testRun: return .blue
        case .needsYou: return .orange
        case .failed: return .red
        }
    }

    private var icon: String {
        switch info.kind {
        case .inStock: return "bell.badge.fill"
        case .ordered: return "checkmark.seal.fill"
        case .testRun: return "checkmark.circle.fill"
        case .needsYou: return "hand.point.up.left.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 64))
                Text(info.kind.title)
                    .font(.system(size: 38, weight: .black))
                    .multilineTextAlignment(.center)
                Text(info.name)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let price = info.price {
                    Text(price).font(.title2.bold())
                }
                if let message = info.message {
                    Text(message)
                        .font(.body)
                        .multilineTextAlignment(.center)
                }
                Button {
                    if info.kind == .inStock {
                        monitor.openAlarmItem()
                    } else {
                        monitor.dismissAlarm()
                    }
                } label: {
                    Text(primaryLabel)
                        .font(.title3.bold())
                        .foregroundColor(background)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                }
                if info.kind == .inStock {
                    Button("I bought it: move to Bought") {
                        monitor.markBought(info.itemID)
                    }
                    .font(.headline)
                    Button("Dismiss (keep on list)") {
                        monitor.dismissAlarm()
                    }
                    .font(.subheadline)
                }
            }
            .foregroundColor(.white)
            .padding(32)
        }
    }

    private var primaryLabel: String {
        switch info.kind {
        case .inStock: return "Open in Lazada"
        case .needsYou: return "Show me the page"
        default: return "OK"
        }
    }
}
