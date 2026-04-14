import Foundation

/// Peak hours: Weekdays 5am-11am PT / 1pm-7pm GMT = 12:00-18:00 UTC
enum PeakHours {
    static let startHourUTC = 12
    static let endHourUTC = 18

    struct Status {
        let isPeak: Bool
        let timeUntilChange: TimeInterval // time until peak starts or ends

        var changeDescription: String {
            let hours = Int(timeUntilChange) / 3600
            let minutes = (Int(timeUntilChange) % 3600) / 60
            if isPeak {
                if hours > 0 {
                    return "Peak ends in \(hours)h \(minutes)m"
                }
                return "Peak ends in \(minutes)m"
            } else {
                if hours > 0 {
                    return "Next peak in \(hours)h \(minutes)m"
                }
                return "Next peak in \(minutes)m"
            }
        }
    }

    /// Check if the given date is during peak hours (weekdays 12:00-18:00 UTC).
    static func status(at date: Date = Date()) -> Status {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        let weekday = utcCalendar.component(.weekday, from: date) // 1=Sun, 7=Sat
        let hour = utcCalendar.component(.hour, from: date)
        let minute = utcCalendar.component(.minute, from: date)
        let isWeekday = weekday >= 2 && weekday <= 6 // Mon-Fri

        let currentMinutes = hour * 60 + minute
        let peakStartMinutes = startHourUTC * 60
        let peakEndMinutes = endHourUTC * 60

        if isWeekday && currentMinutes >= peakStartMinutes && currentMinutes < peakEndMinutes {
            // Currently in peak hours
            let minutesUntilEnd = peakEndMinutes - currentMinutes
            return Status(isPeak: true, timeUntilChange: Double(minutesUntilEnd * 60))
        } else {
            // Not in peak hours - calculate time until next peak
            let timeUntilNextPeak = timeUntilNextPeakStart(from: date, calendar: utcCalendar)
            return Status(isPeak: false, timeUntilChange: timeUntilNextPeak)
        }
    }

    private static func timeUntilNextPeakStart(from date: Date, calendar: Calendar) -> TimeInterval {
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let currentMinutes = hour * 60 + minute
        let peakStartMinutes = startHourUTC * 60

        // If it's a weekday and before peak, peak starts today
        let isWeekday = weekday >= 2 && weekday <= 6
        if isWeekday && currentMinutes < peakStartMinutes {
            return Double((peakStartMinutes - currentMinutes) * 60)
        }

        // Otherwise find the next weekday
        var daysAhead = 1
        var nextWeekday = weekday % 7 + 1
        while nextWeekday == 1 || nextWeekday == 7 { // Skip Sun(1) and Sat(7)
            daysAhead += 1
            nextWeekday = nextWeekday % 7 + 1
        }

        // Next peak is daysAhead days from now at peakStartMinutes
        let minutesLeftToday = 24 * 60 - currentMinutes
        let fullDays = (daysAhead - 1) * 24 * 60
        let totalMinutes = minutesLeftToday + fullDays + peakStartMinutes
        return Double(totalMinutes * 60)
    }
}
