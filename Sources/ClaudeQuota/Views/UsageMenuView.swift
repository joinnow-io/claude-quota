import AppKit
import SwiftUI

struct UsageMenuView: View {
    @Bindable var store: QuotaStore
    @State private var tokenCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Claude Code Usage")
                    .font(.headline)
                Spacer()
                if let creds = store.credentials {
                    Text(creds.tierDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            Divider()

            switch store.quotaState {
            case .loading:
                loadingSection
            case .error(let msg):
                errorSection(msg)
            case .loaded(let quota):
                limitSections(quota: quota)
            }

            // Local data sections (only if enabled and loaded)
            if let snapshot = store.snapshot, store.showLocalData {
                Divider()
                todaySection(snapshot)
            }

            Divider()

            actionsSection
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Loading / Error

    @ViewBuilder
    private var loadingSection: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Fetching quota...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Could not fetch quota")
                    .font(.subheadline.weight(.semibold))
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") { store.fetchAPIQuota(force: true) }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Limit sections (dynamic)

    @ViewBuilder
    private func limitSections(quota: UsageAPIResponse) -> some View {
        let keys = LimitKind.sorted(Array(quota.limits.keys)).filter { !store.popoverHidden(for: $0) }
        ForEach(Array(keys.enumerated()), id: \.element) { index, key in
            if let window = quota.limits[key] {
                limitSection(key: key, window: window)
                if index < keys.count - 1 {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func limitSection(key: String, window: UsageAPIResponse.WindowQuota) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LimitKind.name(for: key))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if key == "five_hour", store.peakStatus.isPeak {
                    peakBadge
                }
            }

            percentageBar(utilization: window.utilization)

            if let resetsAt = window.resetsAtDate {
                Text("Resets in \(Formatting.timeRemaining(resetsAt.timeIntervalSince(store.now)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if key == "five_hour", store.peakStatus.isPeak {
                Button(action: { NSWorkspace.shared.open(Links.peakHours) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(store.peakStatus.changeDescription)
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }

            // Local JSONL breakdown is only meaningful for the built-in windows.
            if let snapshot = store.snapshot {
                if key == "five_hour" {
                    modelBreakdown(snapshot.fiveHour)
                } else if key == "seven_day" {
                    if snapshot.sevenDay.messageCount > 0 {
                        Text("\(Formatting.tokensDetailed(snapshot.sevenDay.messageCount)) messages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    modelBreakdown(snapshot.sevenDay)
                }
            }
        }
    }

    // MARK: - Today

    @ViewBuilder
    private func todaySection(_ snapshot: UsageSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.subheadline.weight(.semibold))
                if snapshot.today.total.totalTokens > 0 {
                    Text("\(Formatting.tokens(snapshot.today.total.totalTokens)) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No usage yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if snapshot.today.total.totalTokens > 0 {
                Text("~\(CostEstimator.formatCost(CostEstimator.estimateCost(window: snapshot.today)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { store.fetchAPIQuota(force: true) }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
            }
            .buttonStyle(.plain)
            .font(.caption)

            Button(action: { copyToken() }) {
                HStack(spacing: 4) {
                    Image(systemName: tokenCopied ? "checkmark" : "key")
                    Text(tokenCopied ? "Copied!" : "Copy Token")
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .disabled(store.credentials?.accessToken == nil)

            Toggle("Local Details", isOn: Binding(
                get: { store.showLocalData },
                set: { _ in store.toggleLocalData() }
            ))
            .font(.caption)
            .toggleStyle(.checkbox)

            Toggle("Launch at Login", isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.setEnabled($0) }
            ))
            .font(.caption)
            .toggleStyle(.checkbox)

            Toggle("Slow sync (every 5 min)", isOn: Binding(
                get: { store.slowSync },
                set: { _ in store.toggleSlowSync() }
            ))
            .font(.caption)
            .toggleStyle(.checkbox)
            .help("When off, ClaudeQuota polls the usage API every 60 seconds. When on, it polls every 5 minutes — easier on rate limits and battery, at the cost of slightly stale numbers.")

            Toggle("Auto-refresh tokens (experimental)", isOn: Binding(
                get: { store.allowKeychainWrites },
                set: { _ in store.toggleAllowKeychainWrites() }
            ))
            .font(.caption)
            .toggleStyle(.checkbox)
            .help("When off, this app never writes to the Claude Code keychain entry. When on, it refreshes expired OAuth tokens and writes only accessToken / refreshToken / expiresAt back — skipping the write when values already match. If credentials expire, the safer path is to open Claude Code to refresh them.")

            displaySettings

            Divider()

            Button(action: { NSWorkspace.shared.open(Links.about) }) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text("About ClaudeQuota")
                }
            }
            .buttonStyle(.plain)
            .font(.caption)

            Button("Quit ClaudeQuota") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Display settings

    @ViewBuilder
    private var displaySettings: some View {
        // Merge currently-returned keys with any we've ever seen so toggles
        // don't disappear if a limit drops out of a response.
        let liveKeys = store.apiQuota.map { Array($0.limits.keys) } ?? []
        let keys = LimitKind.sorted(Array(Set(liveKeys).union(store.knownLimitKeys)))

        if !keys.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(keys, id: \.self) { key in
                        limitDisplayRow(key: key)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Display")
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func limitDisplayRow(key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(LimitKind.name(for: key), isOn: Binding(
                get: { !store.popoverHidden(for: key) },
                set: { store.setPopoverHidden(!$0, for: key) }
            ))
            .font(.caption)
            .toggleStyle(.checkbox)

            HStack {
                Text("Menu bar:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { store.menuBarDisplay(for: key) },
                    set: { store.setMenuBarDisplay($0, for: key) }
                )) {
                    ForEach(LimitDisplay.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.caption2)
            }
            .padding(.leading, 18)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func percentageBar(utilization: Double) -> some View {
        let fraction = utilization / 100.0
        let color = barColor(fraction: fraction)

        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: min(geo.size.width, geo.size.width * fraction), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Spacer()
                Text("\(Int(utilization.rounded()))%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
            }
        }
    }

    @ViewBuilder
    private func modelBreakdown(_ window: WindowUsage) -> some View {
        let models = window.modelBreakdown.prefix(3)
        if !models.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    HStack(spacing: 4) {
                        Text(index == models.count - 1 ? "└" : "├")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.quaternary)
                        Text(model.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatting.tokens(model.tokens.totalTokens))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var peakBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
            Text("PEAK")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(.orange)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func copyToken() {
        guard let token = store.credentials?.accessToken else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        tokenCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            tokenCopied = false
        }
    }

    private func barColor(fraction: Double) -> Color {
        if fraction >= 0.95 { return .red }
        if fraction >= 0.80 { return .orange }
        return .green
    }

    private enum Links {
        static let about = URL(string: "https://joinnow-io.github.io/claude-quota/")!
        static let peakHours = URL(string: "https://joinnow-io.github.io/claude-quota/#peak-hours")!
    }
}
