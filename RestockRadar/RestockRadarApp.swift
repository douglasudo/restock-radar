import SwiftUI

@main
struct RestockRadarApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ItemStore()
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(monitor)
                .onAppear {
                    monitor.attach(store)
                    store.importCatalogIfNeeded()
                    Notifier.requestPermission()
                }
        }
    }
}
