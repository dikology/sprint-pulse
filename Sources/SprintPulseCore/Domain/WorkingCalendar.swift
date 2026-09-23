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

    // MARK: - The current Working Day (#12)

    /// The Working Day `date` belongs to — or, when it belongs to none (a weekend, a declared
    /// Non-Working Date), the most recent one before it. Returned at local midnight.
    ///
    /// This is the day a reading is judged against: Saturday's current Working Day is Friday,
    /// because Friday is the day the sprint was last burning on.
    ///
    /// The search back is bounded at a year, because "the most recent Working Day before today"
    /// has no answer on a calendar that declares none — an empty `workingWeekdays`, or a shutdown
    /// the Operator marked off for longer than a year. `nil` says that out loud rather than
    /// returning a day that is not one, and `predatesCurrentWorkingDay` turns it into `Unknown`,
    /// which invariant 7 prefers to a guess. A shutdown of ordinary length — a factory's fortnight,
    /// a national holiday run — is found its other side of.
    public func currentWorkingDay(for date: Date) -> Date? {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<366 {
            if isWorkingDay(day) { return day }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else {
                return nil
            }
            day = previous
        }
        return nil
    }

    /// Rule 1's stale-data trigger (`docs/agents/glossary.md`, #12): was data taken at `readAt`
    /// read *before* the current Working Day — the one `now` falls in?
    ///
    /// The day, not the hour, is the unit: a burn rate is measured in Working Days, so Points read
    /// at 09:00 are still today's Points at 17:00, and Points read at 23:59 yesterday are not.
    /// Nothing is counted — this is one comparison against `currentWorkingDay(for: now)`, so a
    /// declared holiday and a weekend both mean the same thing: the last day the sprint was
    /// burning on is the one the data is judged against.
    ///
    /// A pattern with no Working Day in it at all is reported as predating: `Unknown` is always
    /// preferred to a guess (CONTEXT invariant 7), and there is no day to be current in.
    public func predatesCurrentWorkingDay(readAt: Date, now: Date) -> Bool {
        guard let startOfCurrentWorkingDay = currentWorkingDay(for: now) else { return true }
        return readAt < startOfCurrentWorkingDay
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
