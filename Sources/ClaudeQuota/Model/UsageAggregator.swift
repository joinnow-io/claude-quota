import Foundation

/// Scans Claude Code JSONL session files and aggregates token usage by time windows.
actor UsageAggregator {
    private let projectsDir: String
    private var fileOffsets: [String: UInt64] = [:] // byte offset per file for incremental reads

    init(projectsDir: String = NSHomeDirectory() + "/.claude/projects") {
        self.projectsDir = projectsDir
    }

    /// Full scan: read all JSONL files and aggregate into time windows.
    func fullScan() -> UsageSnapshot {
        fileOffsets.removeAll()
        return scan()
    }

    /// Incremental scan: only read new data from files that changed.
    func incrementalScan() -> UsageSnapshot {
        return scan()
    }

    private func scan() -> UsageSnapshot {
        let now = Date()
        let fiveHourWindow = RateLimitWindow.currentFiveHourWindow(at: now)
        let sevenDayStart = RateLimitWindow.sevenDayWindowStart(at: now)
        let todayStart = RateLimitWindow.todayStart(at: now)

        let sevenDayWindow = RateLimitWindow.currentSevenDayWindow(at: now)

        var snapshot = UsageSnapshot()
        snapshot.fiveHourWindow = fiveHourWindow
        snapshot.sevenDayWindow = sevenDayWindow
        snapshot.lastUpdated = now

        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else {
            return snapshot
        }

        for projectDir in projectDirs {
            let projectPath = (projectsDir as NSString).appendingPathComponent(projectDir)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            guard let files = try? fm.contentsOfDirectory(atPath: projectPath) else {
                continue
            }

            for file in files where file.hasSuffix(".jsonl") {
                let filePath = (projectPath as NSString).appendingPathComponent(file)
                parseJSONLFile(
                    filePath,
                    fiveHourWindow: fiveHourWindow,
                    sevenDayStart: sevenDayStart,
                    todayStart: todayStart,
                    into: &snapshot
                )
            }
        }

        return snapshot
    }

    private func parseJSONLFile(
        _ path: String,
        fiveHourWindow: RateLimitWindow.FiveHourWindow,
        sevenDayStart: Date,
        todayStart: Date,
        into snapshot: inout UsageSnapshot
    ) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { handle.closeFile() }

        // Seek to last known offset for incremental reads
        let offset = fileOffsets[path] ?? 0
        if offset > 0 {
            handle.seek(toFileOffset: offset)
        }

        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }

        // Update offset
        fileOffsets[path] = handle.offsetInFile

        // Parse lines
        guard let text = String(data: data, encoding: .utf8) else { return }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            guard let message = parseAssistantMessage(line, isoFormatter: isoFormatter, isoFormatterNoFrac: isoFormatterNoFrac) else {
                continue
            }

            // Aggregate into windows
            if message.timestamp >= fiveHourWindow.start && message.timestamp < fiveHourWindow.end {
                snapshot.fiveHour.add(tokens: message.usage, model: message.model)
            }

            if message.timestamp >= sevenDayStart {
                snapshot.sevenDay.add(tokens: message.usage, model: message.model)
            }

            if message.timestamp >= todayStart {
                snapshot.today.add(tokens: message.usage, model: message.model)
            }
        }
    }

    private func parseAssistantMessage(
        _ line: String,
        isoFormatter: ISO8601DateFormatter,
        isoFormatterNoFrac: ISO8601DateFormatter
    ) -> SessionMessage? {
        guard let data = line.data(using: .utf8) else { return nil }

        // Quick check: only parse assistant messages with usage
        guard line.contains("\"type\":\"assistant\"") || line.contains("\"type\": \"assistant\"") else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard json["type"] as? String == "assistant",
              let timestampStr = json["timestamp"] as? String,
              let message = json["message"] as? [String: Any],
              let usageDict = message["usage"] as? [String: Any] else {
            return nil
        }

        guard let timestamp = isoFormatter.date(from: timestampStr)
                ?? isoFormatterNoFrac.date(from: timestampStr) else {
            return nil
        }

        let model = message["model"] as? String ?? "unknown"

        let usage = TokenUsage(
            inputTokens: usageDict["input_tokens"] as? Int ?? 0,
            outputTokens: usageDict["output_tokens"] as? Int ?? 0,
            cacheCreationInputTokens: usageDict["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadInputTokens: usageDict["cache_read_input_tokens"] as? Int ?? 0
        )

        return SessionMessage(timestamp: timestamp, model: model, usage: usage)
    }
}
