import Foundation

enum RateLimitWindow {
    /// Fixed 5-hour windows aligned to UTC schedule.
    /// Observed from rate_limit_event: resets at 21:00 UTC → windows are 01, 06, 11, 16, 21 UTC.
    struct FiveHourWindow: Equatable {
        let start: Date
        let end: Date

        var timeRemaining: TimeInterval {
            max(0, end.timeIntervalSinceNow)
        }

        var progress: Double {
            let total = end.timeIntervalSince(start)
            let elapsed = Date().timeIntervalSince(start)
            return min(1.0, max(0.0, elapsed / total))
        }
    }

    /// The fixed UTC hours where 5-hour windows start: 1, 6, 11, 16, 21
    static let windowStartHours = [1, 6, 11, 16, 21]

    /// Returns the current 5-hour window based on the given date.
    static func currentFiveHourWindow(at date: Date = Date()) -> FiveHourWindow {
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        let hour = utcCalendar.component(.hour, from: date)

        // Find which window we're in
        var windowStartHour = windowStartHours.last! // 21
        for h in windowStartHours {
            if hour < h {
                break
            }
            windowStartHour = h
        }

        // Build the start date
        var startComponents = utcCalendar.dateComponents([.year, .month, .day], from: date)
        startComponents.hour = windowStartHour
        startComponents.minute = 0
        startComponents.second = 0
        startComponents.timeZone = TimeZone(identifier: "UTC")

        var start = utcCalendar.date(from: startComponents)!

        // If current window started yesterday (e.g., 21:00 yesterday and it's now 00:30)
        if start > date {
            start = utcCalendar.date(byAdding: .day, value: -1, to: start)!
        }

        let end = start.addingTimeInterval(5 * 3600)

        return FiveHourWindow(start: start, end: end)
    }

    /// Fixed 7-day window aligned to a weekly schedule.
    /// Observed: Claude shows "resets 1d" on Tuesday evening UTC, suggesting Wednesday 00:00 UTC reset.
    struct SevenDayWindow: Equatable {
        let start: Date
        let end: Date

        var timeRemaining: TimeInterval {
            max(0, end.timeIntervalSinceNow)
        }
    }

    /// Returns the current 7-day window. Resets every Thursday at 14:00 UTC.
    /// Observed from Claude's built-in usage display: "Resets Thu 4:00 PM" CEST = 14:00 UTC.
    static func currentSevenDayWindow(at date: Date = Date()) -> SevenDayWindow {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        // Find the most recent Thursday 14:00 UTC at or before `date`
        let weekday = utcCalendar.component(.weekday, from: date) // 1=Sun, 5=Thu

        let daysSinceThursday: Int
        if weekday >= 5 {
            daysSinceThursday = weekday - 5
        } else {
            daysSinceThursday = weekday + 2 // days since last Thursday
        }

        var startComponents = utcCalendar.dateComponents([.year, .month, .day], from: date)
        startComponents.hour = 14
        startComponents.minute = 0
        startComponents.second = 0
        startComponents.timeZone = TimeZone(identifier: "UTC")
        var candidate = utcCalendar.date(from: startComponents)!
        candidate = utcCalendar.date(byAdding: .day, value: -daysSinceThursday, to: candidate)!

        // If the candidate is in the future, go back 7 days
        if candidate > date {
            candidate = utcCalendar.date(byAdding: .day, value: -7, to: candidate)!
        }

        let start = candidate
        let end = utcCalendar.date(byAdding: .day, value: 7, to: start)!

        return SevenDayWindow(start: start, end: end)
    }

    /// Returns the start of the 7-day window for message filtering (uses the fixed window start).
    static func sevenDayWindowStart(at date: Date = Date()) -> Date {
        currentSevenDayWindow(at: date).start
    }

    /// Returns the start of today in UTC.
    static func todayStart(at date: Date = Date()) -> Date {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        return utcCalendar.startOfDay(for: date)
    }
}
