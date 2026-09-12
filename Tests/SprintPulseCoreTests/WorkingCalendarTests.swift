import XCTest
@testable import SprintPulseCore

final class WorkingCalendarTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    // MARK: - isWorkingDay

    func test_default_isMondayToFridayWithNoNonWorkingDates() {
        let calendar = WorkingCalendar(timeZone: utc)

        XCTAssertTrue(calendar.isWorkingDay(isoDate("2026-09-09T00:00:00Z")), "Wednesday")
        XCTAssertFalse(calendar.isWorkingDay(isoDate("2026-09-12T00:00:00Z")), "Saturday")
        XCTAssertFalse(calendar.isWorkingDay(isoDate("2026-09-13T00:00:00Z")), "Sunday")
    }

    func test_isWorkingDay_excludesADeclaredNonWorkingDate() {
        // Wednesday 2026-09-09 declared a holiday.
        let calendar = WorkingCalendar(
            nonWorkingDates: [isoDate("2026-09-09T00:00:00Z")],
            timeZone: utc
        )

        XCTAssertFalse(calendar.isWorkingDay(isoDate("2026-09-09T15:00:00Z")), "same day, later time")
        XCTAssertTrue(calendar.isWorkingDay(isoDate("2026-09-16T09:00:00Z")), "the following Wednesday is untouched")
    }

    func test_customWorkingWeekdays_supportsANonStandardWorkingWeek() {
        // Sunday–Thursday, Friday/Saturday as the weekend.
        let calendar = WorkingCalendar(workingWeekdays: [1, 2, 3, 4, 5], timeZone: utc)

        XCTAssertTrue(calendar.isWorkingDay(isoDate("2026-09-13T00:00:00Z")), "Sunday")
        XCTAssertTrue(calendar.isWorkingDay(isoDate("2026-09-10T00:00:00Z")), "Thursday")
        XCTAssertFalse(calendar.isWorkingDay(isoDate("2026-09-11T00:00:00Z")), "Friday")
        XCTAssertFalse(calendar.isWorkingDay(isoDate("2026-09-12T00:00:00Z")), "Saturday")
    }

    // MARK: - Working Days Remaining

    func test_workingDaysRemaining_aSprintSpanningAWeekendExcludesTheWeekend() {
        let calendar = WorkingCalendar(timeZone: utc)

        // Fri 09-11 through Mon 09-14: Sat/Sun excluded, Fri and Mon remain.
        let remaining = calendar.workingDaysRemaining(
            now: isoDate("2026-09-11T09:00:00Z"),
            sprintEnd: isoDate("2026-09-14T17:00:00Z")
        )

        XCTAssertEqual(remaining, 2)
    }

    func test_workingDaysRemaining_aSprintSpanningADeclaredHolidayExcludesIt() {
        let calendar = WorkingCalendar(
            nonWorkingDates: [isoDate("2026-09-09T00:00:00Z")], // Wednesday
            timeZone: utc
        )

        // Mon 09-07 through Fri 09-11: five weekdays minus the Wednesday holiday.
        let remaining = calendar.workingDaysRemaining(
            now: isoDate("2026-09-07T08:00:00Z"),
            sprintEnd: isoDate("2026-09-11T17:00:00Z")
        )

        XCTAssertEqual(remaining, 4)
    }

    func test_workingDaysRemaining_onTheSprintsFinalDayIsOneWholeDayNotFractional() {
        let calendar = WorkingCalendar(timeZone: utc)

        // "now" sits in the afternoon of the final day; the count must not have decayed.
        let remaining = calendar.workingDaysRemaining(
            now: isoDate("2026-09-11T16:59:00Z"),
            sprintEnd: isoDate("2026-09-11T17:00:00Z")
        )

        XCTAssertEqual(remaining, 1)
    }

    func test_workingDaysRemaining_todayBeingANonWorkingDateExcludesTodayFromTheCount() {
        // Wednesday 2026-09-09 declared a holiday, and it is "today".
        let calendar = WorkingCalendar(
            nonWorkingDates: [isoDate("2026-09-09T00:00:00Z")],
            timeZone: utc
        )

        let remaining = calendar.workingDaysRemaining(
            now: isoDate("2026-09-09T09:00:00Z"),
            sprintEnd: isoDate("2026-09-11T17:00:00Z") // Friday
        )

        XCTAssertEqual(remaining, 2, "only Thursday and Friday count; the holiday today does not")
    }

    func test_workingDaysRemaining_isZeroOnceSprintEndHasPassed() {
        let calendar = WorkingCalendar(timeZone: utc)

        let remaining = calendar.workingDaysRemaining(
            now: isoDate("2026-09-14T09:00:00Z"),
            sprintEnd: isoDate("2026-09-11T17:00:00Z")
        )

        XCTAssertEqual(remaining, 0)
    }

    // MARK: - Working Days Elapsed

    func test_workingDaysElapsed_aSprintSpanningAWeekendExcludesTheWeekend() {
        let calendar = WorkingCalendar(timeZone: utc)

        // Fri 09-11 through Mon 09-14: Sat/Sun excluded, Fri and Mon remain.
        let elapsed = calendar.workingDaysElapsed(
            now: isoDate("2026-09-14T09:00:00Z"),
            sprintStart: isoDate("2026-09-11T09:00:00Z")
        )

        XCTAssertEqual(elapsed, 2)
    }

    func test_workingDaysElapsed_isZeroBeforeTheSprintHasStarted() {
        let calendar = WorkingCalendar(timeZone: utc)

        let elapsed = calendar.workingDaysElapsed(
            now: isoDate("2026-09-11T09:00:00Z"),
            sprintStart: isoDate("2026-09-14T09:00:00Z")
        )

        XCTAssertEqual(elapsed, 0)
    }
}
