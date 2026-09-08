# Confidence is computed over Actionable Points only

Remaining work splits into **Actionable** (`ToDo` + `InProgress`) and **Waiting** (`InReview` +
`OnHold`). The Required Rate, and therefore Confidence, is computed over Actionable Points alone.
Waiting Points are displayed beside the forecast and can cap Confidence, but never enter the
ratio.

Review is genuinely unfinished work that the Operator genuinely cannot move. Counting it at full
weight makes the Required Rate demand points that are not theirs to burn; counting it as done
makes review a rubber stamp.

## Considered options

A fractional weight — counting review Points at, say, 0.3 — was the obvious middle and was
rejected. The multiplier would be a guess dressed as arithmetic, and it destroys the property the
whole project is built on: that every number can be checked by hand from other numbers on screen.

## Consequences

The calibration that review actually warrants is not a weight but two observable facts — bounce
rate (what fraction of `InReview` Issues return to `InProgress`) and review dwell time. Both
belong in the caveat text, never smuggled into the total.

Two states exist only because of this split: `Hands Off` (no Actionable Points remain but Waiting
Points do — the Required Rate is zero and the ratio undefined), and the Waiting-heavy Cap, which
forbids claiming `No Sweat` while more than 40% of remaining work sits in someone else's queue.

It also introduces a known, accepted bias: the Demonstrated Rate counts only Points that reached
`Done`, so effort currently sitting in review is spent but unbanked, and the forecast runs
conservative mid-sprint. Correcting it would mean crediting incomplete work, which is the error
`InReview` exists to prevent.
