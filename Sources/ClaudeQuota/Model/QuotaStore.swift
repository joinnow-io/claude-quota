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

    // Whether this app is allowed to refresh OAuth tokens and write back to the
    // shared `Claude Code-credentials` keychain entry. Off by default to avoid
    // clobbering state Claude Code writes (e.g. connector tokens).
    var allowKeychainWrites: Bool = false

    // Slow sync: poll the API every 5 minutes instead of every 60 seconds.
    // Useful for avoiding rate limits or reducing background work.
    var slowSync: Bool = false

    // Per-limit display preferences (keyed by API snake_case key).
    var menuBarDisplay: [String: LimitDisplay] = [:]
    var popoverHidden: [String: Bool] = [:]

    // LimitKind.knownOrder ∪ current API keys. Not persisted — so renamed
    // limit keys don't linger in the Display picker after a code update.
    var knownLimitKeys: Set<String> = Set(LimitKind.knownOrder)

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
        apiQuota?.fiveHour?.utilization
    }

    var sevenDayPercentage: Double? {
        apiQuota?.sevenDay?.utilization
    }

    var fiveHourTimeRemaining: String? {
        guard let resetsAt = apiQuota?.fiveHour?.resetsAtDate else { return nil }
        return Formatting.timeRemaining(resetsAt.timeIntervalSince(now))
    }

    var sevenDayTimeRemaining: String? {
        guard let resetsAt = apiQuota?.sevenDay?.resetsAtDate else { return nil }
        return Formatting.timeRemaining(resetsAt.timeIntervalSince(now))
    }

    /// Keys visible in the menu bar right now (after filtering hide + thresholds).
    /// Ordered for stable display.
    private func visibleMenuBarKeys(for quota: UsageAPIResponse) -> [String] {
        LimitKind.sorted(Array(quota.limits.keys)).filter { key in
            guard let window = quota.limits[key] else { return false }
            let display = menuBarDisplay(for: key)
            if display == .hide { return false }
            if let threshold = display.threshold, window.utilization < threshold {
                return false
            }
            return true
        }
    }

    /// Empty string when no limits should be shown — the menu bar falls back
    /// to an icon-only label in that case (see ClaudeQuotaApp).
    var menuBarTitle: String {
        guard let quota = apiQuota else {
            if case .error = quotaState { return "— err" }
            return "..."
        }
        let visible = visibleMenuBarKeys(for: quota)
        let segments: [String] = visible.compactMap { key in
            guard let window = quota.limits[key] else { return nil }
            let pct = "\(Int(window.utilization.rounded()))%"
            let time = window.resetsAtDate.map { Formatting.timeRemaining($0.timeIntervalSince(now)) } ?? ""
            return time.isEmpty ? pct : "\(pct) \(time)"
        }
        if segments.isEmpty { return "" }
        let peak = peakStatus.isPeak ? "\u{26A1}" : ""
        return peak + segments.joined(separator: " | ")
    }

    var menuBarColor: MenuBarColor {
        guard let quota = apiQuota else { return .green }
        let visible = visibleMenuBarKeys(for: quota)
        let pctValues = visible.compactMap { quota.limits[$0]?.utilization }
        guard let maxPct = pctValues.max() else { return .green }
        if maxPct >= 95 { return .red }
        if maxPct >= 80 { return .orange }
        return .green
    }

    enum MenuBarColor {
        case green, orange, red
    }

    // MARK: - Per-limit preferences

    func menuBarDisplay(for key: String) -> LimitDisplay {
        if let explicit = menuBarDisplay[key] { return explicit }
        // Defaults: only the two core windows show in the menu bar out of the box.
        return (key == "five_hour" || key == "seven_day") ? .always : .hide
    }

    func setMenuBarDisplay(_ value: LimitDisplay, for key: String) {
        menuBarDisplay[key] = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.menuBarDisplayKey(for: key))
    }

    func popoverHidden(for key: String) -> Bool {
        popoverHidden[key] ?? false
    }

    func setPopoverHidden(_ hidden: Bool, for key: String) {
        popoverHidden[key] = hidden
        UserDefaults.standard.set(hidden, forKey: Self.popoverHiddenKey(for: key))
    }

    private static func menuBarDisplayKey(for key: String) -> String {
        "menuBarDisplay.\(key)"
    }

    private static func popoverHiddenKey(for key: String) -> String {
        "popover.hidden.\(key)"
    }

    private static let knownLimitKeysDefaultsKey = "knownLimitKeys"

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

        startAPITimer()

        startLocalDataIfEnabled()
    }

    private func startAPITimer() {
        apiTimer?.cancel()
        let interval: TimeInterval = slowSync ? 300 : 60
        let api = DispatchSource.makeTimerSource(queue: .main)
        api.schedule(deadline: .now() + interval, repeating: interval)
        api.setEventHandler { [weak self] in
            self?.periodicUpdate()
        }
        api.resume()
        apiTimer = api
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
            loadCredentials()
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
                    self.recordSeenLimitKeys(response.limits.keys)
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

    func toggleSlowSync() {
        slowSync.toggle()
        UserDefaults.standard.set(slowSync, forKey: "slowSync")
        // Recreate the API timer with the new interval.
        if apiTimer != nil {
            startAPITimer()
        }
    }

    func toggleAllowKeychainWrites() {
        allowKeychainWrites.toggle()
        UserDefaults.standard.set(allowKeychainWrites, forKey: "allowKeychainWrites")
        // Clear error if user just enabled refresh
        if allowKeychainWrites, case .error = quotaState {
            fetchAPIQuota(force: true)
        }
    }

    // MARK: - Private

    private func loadCredentials() {
        credentials = KeychainService.readCredentials()
        showLocalData = UserDefaults.standard.object(forKey: "showLocalData") as? Bool ?? true
        allowKeychainWrites = UserDefaults.standard.bool(forKey: "allowKeychainWrites")
        slowSync = UserDefaults.standard.bool(forKey: "slowSync")
        loadLimitPreferences()
    }

    private func loadLimitPreferences() {
        // Purge legacy "knownLimitKeys" defaults entry (pre-real-API keys like
        // "sonnet" / "claude_design"). We derive knownLimitKeys live now.
        UserDefaults.standard.removeObject(forKey: Self.knownLimitKeysDefaultsKey)

        knownLimitKeys = Set(LimitKind.knownOrder)

        let defaults = UserDefaults.standard
        var menuBar: [String: LimitDisplay] = [:]
        var hidden: [String: Bool] = [:]
        for key in knownLimitKeys {
            if let raw = defaults.string(forKey: Self.menuBarDisplayKey(for: key)),
               let value = LimitDisplay(rawValue: raw) {
                menuBar[key] = value
            }
            if defaults.object(forKey: Self.popoverHiddenKey(for: key)) != nil {
                hidden[key] = defaults.bool(forKey: Self.popoverHiddenKey(for: key))
            }
        }
        menuBarDisplay = menuBar
        popoverHidden = hidden
    }

    private func recordSeenLimitKeys(_ keys: some Sequence<String>) {
        // Replace — not formUnion — so keys that disappear from the API (or were
        // wrong guesses in an earlier release) don't linger forever.
        knownLimitKeys = Set(keys).union(LimitKind.knownOrder)

        // Pick up any prefs saved for keys we hadn't seen before.
        let defaults = UserDefaults.standard
        for key in knownLimitKeys where menuBarDisplay[key] == nil {
            if let raw = defaults.string(forKey: Self.menuBarDisplayKey(for: key)),
               let value = LimitDisplay(rawValue: raw) {
                menuBarDisplay[key] = value
            }
        }
        for key in knownLimitKeys where popoverHidden[key] == nil {
            if defaults.object(forKey: Self.popoverHiddenKey(for: key)) != nil {
                popoverHidden[key] = defaults.bool(forKey: Self.popoverHiddenKey(for: key))
            }
        }
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
