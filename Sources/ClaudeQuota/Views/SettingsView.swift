import SwiftUI

struct SettingsView: View {
    @Bindable var store: QuotaStore

    var body: some View {
        Form {
            Section("Plan Information") {
                if let creds = store.credentials {
                    LabeledContent("Plan", value: creds.tierDisplayName)
                    LabeledContent("Rate Limit Tier", value: creds.rateLimitTier ?? "default")
                    LabeledContent("Tier Multiplier", value: "\(creds.tierMultiplier)x")
                } else {
                    Text("No Claude Code credentials found")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Current Quota") {
                if let quota = store.apiQuota {
                    ForEach(LimitKind.sorted(Array(quota.limits.keys)), id: \.self) { key in
                        if let window = quota.limits[key] {
                            LabeledContent("\(LimitKind.name(for: key)) Usage", value: "\(Int(window.utilization))%")
                            if let reset = window.resetsAtDate {
                                LabeledContent("\(LimitKind.name(for: key)) Resets", value: Formatting.timeRemaining(reset.timeIntervalSinceNow))
                            }
                        }
                    }
                } else {
                    Text("Quota not loaded")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Peak Hours") {
                LabeledContent("Schedule", value: "Weekdays 5am-11am PT")
                LabeledContent("UTC", value: "12:00-18:00 UTC")
                let status = PeakHours.status()
                LabeledContent("Status", value: status.isPeak ? "Peak" : "Off-Peak")
                LabeledContent("", value: status.changeDescription)
            }

            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { LaunchAtLogin.setEnabled($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 400)
    }
}
