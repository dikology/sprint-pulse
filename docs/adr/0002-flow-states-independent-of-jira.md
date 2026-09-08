# Flow States are Sprint Pulse's vocabulary, not Jira's

Sprint Pulse defines six Flow States of its own — `ToDo`, `InProgress`, `InReview`, `OnHold`,
`Done`, `Dropped` — and translates Jira status names into them through an Operator-editable
Status Map. Jira's strings appear in the Status Map and nowhere else in the system.

The Operator's workflow has seven statuses that do not correspond one-to-one with any obvious
model (`Backlog`, `Open`, `Need Info`, `In Progress`, `In Review`, `Done`, `Cancelled`), and
workflows get edited by people who are not the Operator. Without the indirection, a renamed
column silently rebuckets work and quietly changes the forecast.

## Consequences

`Dropped` exists as a Flow State specifically because `Cancelled` fits nowhere else, and mapping
it wrongly corrupts the instrument in a way that is hard to notice: mapped to `Done`, the Operator
can reach full confidence by cancelling everything; mapped to `ToDo`, cancelled work sits in the
remaining total forever. `Dropped` Points leave the sprint's remaining total and are never
credited as completed, so a falling remaining figure can always be attributed to finishing work
or shedding it.

A Jira status absent from the map is an `Unmapped Status`. It is surfaced and forces Confidence
to `Unknown` rather than being bucketed by resemblance — guessing here is precisely the silent
corruption the map exists to prevent.

This is expensive to reverse because the vocabulary reaches everything: the forecast, the fixture
corpus, the Intents, and the mascot's states are all written in it.
