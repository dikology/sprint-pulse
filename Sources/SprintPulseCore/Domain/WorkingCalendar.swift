import Foundation

/// The Operator's own working pattern: which weekdays are ordinarily worked, and which specific
/// calendar dates are declared unavailable. A date is a Working Day when it falls on a working
/// weekday and is not a declared Non-Working Date (CONTEXT "Working Day").
///
/// Configurable, but M0 ships only `default` — Monday to Friday, no Non-Working Dates — with no
/// in-app editor; the editor is M1. Held entirely locally: Sprint Pulse never reads a calendar.
public struct WorkingCalendar: Equatable, Sendable {
    /// Weekday numbers as `Calendar` defines them: `1` = Sunday ... `7` = Saturday.
    public let workingWeekdays: Set<Int>
    private let nonWorkingDays: Set<DateComponents>
    private let calendar: Calendar

    /// Monday through Friday, as `Calendar` weekday numbers.
    public static let mondayToFriday: Set<Int> = [2, 3, 4, 5, 6]

    /// - Parameters:
    ///   - workingWeekdays: Defaults to Monday–Friday.
    ///   - nonWorkingDates: Specific calendar dates the Operator has declared unavailable —
    ///     matched by calendar day, not by exact instant.
    ///   - timeZone: The Operator's local time zone, against which "today" and local midnight
    ///     are resolved. Defaults to the device's current zone.
    public init(
        workingWeekdays: Set<Int> = WorkingCalendar.mondayToFriday,
        nonWorkingDates: Set<Date> = [],
        timeZone: TimeZone = .current
    ) {
        self.workingWeekdays = workingWeekdays
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.nonWorkingDays = Set(nonWorkingDates.map {
            calendar.dateComponents([.year, .month, .day], from: $0)
        })
    }

    /// Monday–Friday, no Non-Working Dates, the device's current time zone.
    public static let `default` = WorkingCalendar()

    /// Whether `date` is a Working Day: on a working weekday and not a declared Non-Working
    /// Date. The current date counts as a whole Working Day until local midnight — this looks
    /// only at the calendar day, never at time of day.
    public func isWorkingDay(_ date: Date) -> Bool {
        guard workingWeekdays.contains(calendar.component(.weekday, from: date)) else {
            return false
        }
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return !nonWorkingDays.contains(day)
    }

    /// `WDR` — Working Days Remaining: the count of Working Days in `[today, sprintEnd]`,
    /// inclusive of today. `0` once `sprintEnd` has already passed.
    public func workingDaysRemaining(now: Date, sprintEnd: Date) -> Int {
        workingDays(from: now, through: sprintEnd)
    }

    /// `WDE` — Working Days Elapsed: the count of Working Days in `[sprintStart, today]`,
    /// inclusive of today. `0` before `sprintStart` has begun.
    public func workingDaysElapsed(now: Date, sprintStart: Date) -> Int {
        workingDays(from: sprintStart, through: now)
    }

    /// The count of Working Days in `[from, through]`, inclusive of both ends by calendar day.
    /// `0` when `from` is after `through`.
    private func workingDays(from: Date, through: Date) -> Int {
        var day = calendar.startOfDay(for: from)
        let last = calendar.startOfDay(for: through)
        guard day <= last else { return 0 }

        var count = 0
        while day <= last {
            if isWorkingDay(day) { count += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return count
    }
}
