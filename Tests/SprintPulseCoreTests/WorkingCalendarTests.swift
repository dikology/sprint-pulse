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

    // MARK: - The current Working Day (#12)

    func test_currentWorkingDay_onAWorkingDayIsThatDay() {
        let calendar = WorkingCalendar(timeZone: utc)

        XCTAssertEqual(
            calendar.currentWorkingDay(for: isoDate("2026-09-09T15:45:00Z")),
            isoDate("2026-09-09T00:00:00Z"),
            "a Wednesday afternoon belongs to Wednesday, however late in it"
        )
    }

    func test_currentWorkingDay_resolvesToTheMostRecentOneWhenTodayIsNotAWorkingDay() {
        let calendar = WorkingCalendar(timeZone: utc)

        // Saturday and Sunday belong to no Working Day of their own: the day the instrument
        // judges data against is the Friday the sprint was last burning on.
        let friday = isoDate("2026-09-11T00:00:00Z")
        XCTAssertEqual(calendar.currentWorkingDay(for: isoDate("2026-09-12T12:00:00Z")), friday)
        XCTAssertEqual(calendar.currentWorkingDay(for: isoDate("2026-09-13T12:00:00Z")), friday)
    }

    func test_currentWorkingDay_stepsBackOverADeclaredNonWorkingDate() {
        let calendar = WorkingCalendar(
            nonWorkingDates: [isoDate("2026-09-14T00:00:00Z")], // Monday, a declared holiday
            timeZone: utc
        )

        XCTAssertEqual(
            calendar.currentWorkingDay(for: isoDate("2026-09-14T10:00:00Z")),
            isoDate("2026-09-11T00:00:00Z"),
            "a day the Operator declared unavailable is no Working Day to be current in"
        )
    }

    func test_currentWorkingDay_isNilWhenThePatternHoldsNoWorkingDay() {
        let calendar = WorkingCalendar(workingWeekdays: [], timeZone: utc)

        XCTAssertNil(calendar.currentWorkingDay(for: isoDate("2026-09-09T12:00:00Z")))
    }

    /// A fortnight's shutdown is an ordinary thing for a self-hosted instance to declare, and the
    /// day a reading is judged against still exists on the other side of it. A search that gave up
    /// after a week would report no current Working Day and withdraw a forecast that had nothing to
    /// withdraw for.
    func test_currentWorkingDay_findsTheLastWorkingDayAcrossADeclaredShutdown() {
        // Every date from Mon 24 Aug through Fri 04 Sep declared non-working: a two-week stop.
        let stop = Set(
            (24...31).map { isoDate("2026-08-\($0)T00:00:00Z") }
                + (1...4).map { isoDate("2026-09-\($0)T00:00:00Z") }
        )
        let calendar = WorkingCalendar(nonWorkingDates: stop, timeZone: utc)
        let insideTheStop = isoDate("2026-09-02T12:00:00Z")

        // Wed 02 Sep is inside the stop, as are the Monday and Tuesday around it, so the current
        // Working Day is Friday 21 August — fourteen declared days and a weekend back.
        XCTAssertEqual(
            calendar.currentWorkingDay(for: insideTheStop),
            isoDate("2026-08-21T00:00:00Z")
        )
        XCTAssertFalse(
            calendar.predatesCurrentWorkingDay(readAt: isoDate("2026-08-21T09:00:00Z"), now: insideTheStop),
            "data from the last day the sprint was burning on is that day's data"
        )
        XCTAssertTrue(
            calendar.predatesCurrentWorkingDay(readAt: isoDate("2026-08-20T17:00:00Z"), now: insideTheStop),
            "and Thursday's data predates it, stop or no stop"
        )
    }

    // MARK: - Predates the current Working Day (rule 1's stale-data trigger)

    func test_predatesCurrentWorkingDay_readEarlierOnTheSameWorkingDay_isFresh() {
        let calendar = WorkingCalendar(timeZone: utc)

        XCTAssertFalse(
            calendar.predatesCurrentWorkingDay(
                readAt: isoDate("2026-09-09T08:30:00Z"), now: isoDate("2026-09-09T17:30:00Z")
            )
        )
    }

    func test_predatesCurrentWorkingDay_readOnAnEarlierWorkingDay_isStale() {
        let calendar = WorkingCalendar(timeZone: utc)

        XCTAssertTrue(
            calendar.predatesCurrentWorkingDay(
                readAt: isoDate("2026-09-08T17:59:00Z"), now: isoDate("2026-09-09T00:01:00Z")
            ),
            "one minute past local midnight, the burn rate is yesterday's"
        )
    }

    func test_predatesCurrentWorkingDay_theWeekendBuysNothing() {
        let calendar = WorkingCalendar(timeZone: utc)

        // Thursday's data, judged on Saturday: Friday was a Working Day and passed unread.
        XCTAssertTrue(
            calendar.predatesCurrentWorkingDay(
                readAt: isoDate("2026-09-10T12:00:00Z"), now: isoDate("2026-09-12T12:00:00Z")
            )
        )
        // Friday's data, judged on Saturday: the current Working Day *is* Friday.
        XCTAssertFalse(
            calendar.predatesCurrentWorkingDay(
                readAt: isoDate("2026-09-11T12:00:00Z"), now: isoDate("2026-09-12T12:00:00Z")
            )
        )
        // And on Monday the Friday read is two Working Days behind.
        XCTAssertTrue(
            calendar.predatesCurrentWorkingDay(
                readAt: isoDate("2026-09-11T12:00:00Z"), now: isoDate("2026-09-14T12:00:00Z")
            )
        )
    }

    func test_predatesCurrentWorkingDay_readAtExactlyTheBoundaryOfTheCurrentWorkingDay_isFresh() {
        let calendar = WorkingCalendar(timeZone: utc)

        XCTAssertFalse(
            calendar.predatesCurrentWorkingDay(
                readAt: isoDate("2026-09-09T00:00:00Z"), now: isoDate("2026-09-09T12:00:00Z")
            )
        )
    }

    func test_predatesCurrentWorkingDay_withNoWorkingDayInPattern_isStale() {
        let calendar = WorkingCalendar(workingWeekdays: [], timeZone: utc)

        XCTAssertTrue(
            calendar.predatesCurrentWorkingDay(
                readAt: isoDate("2026-09-09T12:00:00Z"), now: isoDate("2026-09-09T12:00:00Z")
            ),
            "no day to be current in means no way to call the data fresh — invariant 7"
        )
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
