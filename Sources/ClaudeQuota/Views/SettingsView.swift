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
                    LabeledContent("5-Hour Usage", value: "\(Int(quota.fiveHour.utilization))%")
                    if let reset = quota.fiveHour.resetsAtDate {
                        LabeledContent("5-Hour Resets", value: Formatting.timeRemaining(reset.timeIntervalSinceNow))
                    }
                    LabeledContent("7-Day Usage", value: "\(Int(quota.sevenDay.utilization))%")
                    if let reset = quota.sevenDay.resetsAtDate {
                        LabeledContent("7-Day Resets", value: Formatting.timeRemaining(reset.timeIntervalSinceNow))
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
