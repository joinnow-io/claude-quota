import Foundation
import Observation

/// Data state for API quota
enum QuotaState {
    case loading
    case loaded(UsageAPIResponse)
    case error(String)
}

@Observable
final class QuotaStore {
    // API quota (primary source for percentages + reset times)
    var quotaState: QuotaState = .loading
    var apiQuota: UsageAPIResponse? {
        if case .loaded(let q) = quotaState { return q }
        return nil
    }

    // Local JSONL data (optional — model breakdown, today's tokens, cost)
    var snapshot: UsageSnapshot?
    var showLocalData: Bool = true

    // Metadata
    var credentials: ClaudeCredentials?
    var peakStatus: PeakHours.Status = PeakHours.status()

    // Live countdown — updated every second
    var now: Date = Date()

    private let apiService = UsageAPIService()
    private let aggregator = UsageAggregator()
    private var fileWatcher: FileWatcher?
    private var countdownTimer: DispatchSourceTimer?  // 1-second for live countdown
    private var apiTimer: DispatchSourceTimer?         // 60-second for API refresh
    private let projectsDir = NSHomeDirectory() + "/.claude/projects"

    // Rate limit tracking
    private var lastAPIFetch: Date = .distantPast
    private var rateLimitedUntil: Date = .distantPast
    private let minFetchInterval: TimeInterval = 30  // never call more than once per 30s

    // MARK: - Computed

    var fiveHourPercentage: Double? {
        apiQuota?.fiveHour.utilization
    }

    var sevenDayPercentage: Double? {
        apiQuota?.sevenDay.utilization
    }

    var fiveHourTimeRemaining: String? {
        guard let resetsAt = apiQuota?.fiveHour.resetsAtDate else { return nil }
        return Formatting.timeRemaining(resetsAt.timeIntervalSince(now))
    }

    var sevenDayTimeRemaining: String? {
        guard let resetsAt = apiQuota?.sevenDay.resetsAtDate else { return nil }
        return Formatting.timeRemaining(resetsAt.timeIntervalSince(now))
    }

    var menuBarTitle: String {
        guard let quota = apiQuota else {
            if case .error = quotaState { return "— err" }
            return "..."
        }
        let fh = "\(Int(quota.fiveHour.utilization.rounded()))%"
        let sd = "\(Int(quota.sevenDay.utilization.rounded()))%"
        let peak = peakStatus.isPeak ? "\u{26A1}" : ""
        let fhTime = fiveHourTimeRemaining ?? ""
        let sdTime = sevenDayTimeRemaining ?? ""
        return "\(peak)\(fh) \(fhTime) | \(sd) \(sdTime)"
    }

    var menuBarColor: MenuBarColor {
        guard let quota = apiQuota else { return .green }
        let maxPct = max(quota.fiveHour.utilization, quota.sevenDay.utilization)
        if maxPct >= 95 { return .red }
        if maxPct >= 80 { return .orange }
        return .green
    }

    enum MenuBarColor {
        case green, orange, red
    }

    // MARK: - Lifecycle

    func start() {
        loadCredentials()
        fetchAPIQuota()

        // 1-second timer for live countdown
        let countdown = DispatchSource.makeTimerSource(queue: .main)
        countdown.schedule(deadline: .now() + 1, repeating: 1)
        countdown.setEventHandler { [weak self] in
            self?.now = Date()
        }
        countdown.resume()
        countdownTimer = countdown

        // 60-second timer for API refresh
        let api = DispatchSource.makeTimerSource(queue: .main)
        api.schedule(deadline: .now() + 60, repeating: 60)
        api.setEventHandler { [weak self] in
            self?.periodicUpdate()
        }
        api.resume()
        apiTimer = api

        startLocalDataIfEnabled()
    }

    func stop() {
        stopLocalData()
        countdownTimer?.cancel()
        countdownTimer = nil
        apiTimer?.cancel()
        apiTimer = nil
    }

    func fetchAPIQuota(force: Bool = false) {
        let now = Date()
        if force {
            rateLimitedUntil = .distantPast // manual refresh always clears backoff
        }
        guard now >= rateLimitedUntil && (force || now.timeIntervalSince(lastAPIFetch) >= minFetchInterval) else {
            return
        }
        guard let creds = credentials else {
            quotaState = .error("No credentials")
            return
        }
        lastAPIFetch = now
        Task {
            do {
                let response = try await apiService.fetchUsage(credentials: creds)
                await MainActor.run {
                    self.quotaState = .loaded(response)
                }
            } catch UsageAPIError.rateLimited {
                await MainActor.run {
                    self.rateLimitedUntil = Date().addingTimeInterval(300)
                    if self.apiQuota == nil {
                        self.quotaState = .error("Rate limited — retrying in 5 minutes")
                    }
                }
            } catch {
                await MainActor.run {
                    if self.apiQuota == nil {
                        self.quotaState = .error(error.localizedDescription)
                    }
                }
            }
        }
    }

    func toggleLocalData() {
        showLocalData.toggle()
        UserDefaults.standard.set(showLocalData, forKey: "showLocalData")
        if showLocalData {
            startLocalDataIfEnabled()
        } else {
            stopLocalData()
            snapshot = nil
        }
    }

    // MARK: - Private

    private func loadCredentials() {
        credentials = KeychainService.readCredentials()
        showLocalData = UserDefaults.standard.object(forKey: "showLocalData") as? Bool ?? true
    }

    private func startLocalDataIfEnabled() {
        guard showLocalData else { return }

        // Initial scan
        refreshLocalData()

        // File watcher
        if fileWatcher == nil {
            fileWatcher = FileWatcher(path: projectsDir) { [weak self] in
                DispatchQueue.main.async {
                    guard self?.showLocalData == true else { return }
                    self?.refreshLocalData()
                    // Rate-limited: only fetch API if enough time has passed
                    self?.fetchAPIQuota()
                }
            }
            fileWatcher?.start()
        }
    }

    private func stopLocalData() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    private func refreshLocalData() {
        guard showLocalData else { return }
        Task {
            let result = await aggregator.fullScan()
            await MainActor.run {
                self.snapshot = result
            }
        }
    }

    private func periodicUpdate() {
        peakStatus = PeakHours.status()
        fetchAPIQuota()

        if showLocalData {
            refreshLocalData()
        }

        // Re-read keychain every 5 minutes
        let minute = Calendar.current.component(.minute, from: Date())
        if minute % 5 == 0 {
            loadCredentials()
        }
    }
}
