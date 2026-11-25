import SwiftUI
import WebKit

extension StockStatus {
    var color: Color {
        switch self {
        case .inStock: return .green
        case .outOfStock: return .gray
        case .blocked: return .orange
        case .error: return .red
        case .unknown: return .secondary
        }
    }
}

struct StatusPill: View {
    let status: StockStatus
    var isChecking = false

    var body: some View {
        HStack(spacing: 4) {
            if isChecking {
                ProgressView().controlSize(.mini)
            }
            Text(isChecking ? "Checking" : status.label)
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundColor(color)
        .background(Capsule().fill(color.opacity(0.18)))
    }

    private var color: Color { isChecking ? .blue : status.color }
}

struct IntervalPicker: View {
    @Binding var seconds: Int
    static let options = [15, 30, 60, 120, 300, 600, 900, 1800]

    var body: some View {
        Picker("Check every", selection: $seconds) {
            ForEach(Self.options, id: \.self) { s in
                Text(Self.label(s)).tag(s)
            }
        }
    }

    static func label(_ s: Int) -> String {
        if s < 60 { return "\(s) seconds" }
        if s == 60 { return "1 minute" }
        return "\(s / 60) minutes"
    }
}

/// "checked 12s ago · next in 48s", ticking every second.
struct CountdownText: View {
    @EnvironmentObject private var monitor: Monitor
    let item: WatchItem

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            Text(label(now: context.date))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    @MainActor
    private func label(now: Date) -> String {
        var parts: [String] = []
        if let last = item.lastChecked {
            parts.append("checked \(Self.short(now.timeIntervalSince(last))) ago")
        } else {
            parts.append("not checked yet")
        }
        if monitor.isRunning, item.isEnabled, let due = monitor.nextDue[item.id] {
            let s = due.timeIntervalSince(now)
            parts.append(s > 0 ? "next in \(Self.short(s))" : "queued")
        }
        return parts.joined(separator: " · ")
    }

    static func short(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}

/// Puts the monitor's single shared browser on screen.
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
