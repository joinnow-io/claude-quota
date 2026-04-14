import SwiftUI

struct UsageMenuView: View {
    @Bindable var store: QuotaStore

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
                fiveHourSection(quota.fiveHour)
                Divider()
                sevenDaySection(quota.sevenDay)
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

    // MARK: - 5-Hour Window

    @ViewBuilder
    private func fiveHourSection(_ quota: UsageAPIResponse.WindowQuota) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("5-Hour Window")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if store.peakStatus.isPeak {
                    peakBadge
                }
            }

            percentageBar(utilization: quota.utilization)

            if let resetsAt = quota.resetsAtDate {
                Text("Resets in \(Formatting.timeRemaining(resetsAt.timeIntervalSince(store.now)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.peakStatus.isPeak {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(store.peakStatus.changeDescription)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let snapshot = store.snapshot {
                modelBreakdown(snapshot.fiveHour)
            }
        }
    }

    // MARK: - 7-Day Window

    @ViewBuilder
    private func sevenDaySection(_ quota: UsageAPIResponse.WindowQuota) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("7-Day Window")
                .font(.subheadline.weight(.semibold))

            percentageBar(utilization: quota.utilization)

            if let resetsAt = quota.resetsAtDate {
                Text("Resets in \(Formatting.timeRemaining(resetsAt.timeIntervalSince(store.now)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let snapshot = store.snapshot, snapshot.sevenDay.messageCount > 0 {
                Text("\(Formatting.tokensDetailed(snapshot.sevenDay.messageCount)) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                modelBreakdown(snapshot.sevenDay)
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

            Divider()

            Button("Quit ClaudeQuota") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
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

    private func barColor(fraction: Double) -> Color {
        if fraction >= 0.95 { return .red }
        if fraction >= 0.80 { return .orange }
        return .green
    }
}
