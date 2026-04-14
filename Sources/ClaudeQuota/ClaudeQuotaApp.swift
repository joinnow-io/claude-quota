import SwiftUI
import AppKit

@main
struct ClaudeQuotaApp: App {
    @State private var store = QuotaStore()

    init() {
        // Hide from Dock - menu bar only app
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(store: store)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }

    private var menuBarLabel: some View {
        let color: Color = {
            switch store.menuBarColor {
            case .green: return .green
            case .orange: return .orange
            case .red: return .red
            }
        }()

        return HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(store.menuBarTitle)
                .font(.caption.monospacedDigit())
        }
        .onAppear {
            store.start()
        }
    }
}
