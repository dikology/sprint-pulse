# Sprint Pulse — Precise Definitions

[`CONTEXT.md`](../../CONTEXT.md) is the ubiquitous language: what each term *means*. This file is
the operational companion: exact arithmetic, evaluation order, and edge cases. Where the two
disagree, `CONTEXT.md` defines the term and this file is wrong.

Every definition here is scoped to **My Work** — the Issues in the Active Sprint assigned to the
Operator. Team Scope enters no formula on this page.

## Sets

Let the Issues of My Work be partitioned by Flow State. Sub-tasks are not Issues and appear in no
set. Issues in an `Unmapped Status` appear in no set (see `Unknown`, below).

| Symbol | Definition |
| --- | --- |
| `todo` | Issues in Flow State `ToDo` |
| `wip` | Issues in `InProgress` |
| `review` | Issues in `InReview` |
| `hold` | Issues in `OnHold` |
| `done` | Issues in `Done` |
| `dropped` | Issues in `Dropped` |

**Actionable set** = `todo ∪ wip`. **Waiting set** = `review ∪ hold`.

## Points

`Points(S)` is the sum of Estimates over the Issues of set `S`. An Issue with no Estimate
contributes nothing to any sum — it is never coerced to zero-as-a-value.

| Symbol | Definition |
| --- | --- |
| `A` | `Points(Actionable set)` — Actionable Points |
| `W` | `Points(Waiting set)` — Waiting Points |
| `C` | `Points(done)` — Completed Points |
| `X` | `Points(dropped)` — Dropped Points |
| `U` | **count** (not Points) of Issues in `Actionable ∪ Waiting` with no Estimate |

`X` is excluded from every remaining total and is never added to `C`. Dropped work reduces the
sprint; it does not complete it.

`U` is a count of Issues, not a sum of Points, because its whole purpose is to express an unknown
magnitude. Unestimated Issues in `done` or `dropped` are not counted — they can no longer affect
the outcome.

## Time

A **Working Day** is a calendar date falling on a configured working weekday (default Mon–Fri)
and not present in the Operator's local Non-Working Date list. Sprint bounds come from Jira's
sprint object.

| Symbol | Definition |
| --- | --- |
| `WDR` | Working Days Remaining — count of Working Days in `[today, sprintEnd]`, **inclusive of today** |
| `WDE` | Working Days Elapsed — count of Working Days in `[sprintStart, today]`, **inclusive of today** |

Today counts as a whole Working Day until local midnight. It is deliberately not fractional:
fractional days make the forecast drift downward through the afternoon, which reads as anxiety
rather than information.

## Rates

```
Required Rate      R  = A / WDR                    (defined when WDR > 0)
Demonstrated Rate  D  = C / WDE                    (defined when WDE ≥ 2 and C > 0)
ratio                 = D / R                      (defined when both are)
```

**A known bias:** `R` is measured over Actionable Points while `D` is measured over Completed
Points, and work currently sitting in `review` was burned by the Operator but is not yet banked
in `C`. `D` therefore understates real throughput whenever the Waiting set is non-empty, making
the forecast **conservative mid-sprint**. This is accepted rather than corrected — the correction
would require crediting work that has not actually completed, which is the exact error the
`InReview` Flow State exists to prevent.

## Confidence States

Evaluated in this order. The first matching rule wins; evaluation stops there.

| # | Condition | Confidence State |
| --- | --- | --- |
| 1 | Any Issue in My Work has an `Unmapped Status`, **or** the cache predates the current Working Day | `Unknown` |
| 2 | `A = 0` and `W = 0` | `Finished` |
| 3 | `A = 0` and `W > 0` | `Hands Off` |
| 4 | `WDE < 2` **or** `C = 0` | `Unknown` |
| 5 | `WDR = 0` (and `A > 0`) | `Off Track` |
| 6 | `ratio ≥ 1.25` | `No Sweat` |
| 7 | `1.00 ≤ ratio < 1.25` | `On Track` |
| 8 | `0.75 ≤ ratio < 1.00` | `Tight` |
| 9 | `ratio < 0.75` | `Off Track` |

Rules 1–5 exist so the function is total: no combination of inputs can leave Confidence
undefined, and no undefined arithmetic (`A/0`, `C/0`) is ever reached.

`Unknown` is a first-class answer, not a failure. It is always preferred to a guess.

## Caps

A **Cap** demotes the Confidence State by exactly one band along
`No Sweat → On Track → Tight → Off Track`. Caps never promote. `Off Track` cannot demote further.
`Unknown`, `Hands Off`, and `Finished` are never demoted — they are not points on the scale.

Caps are evaluated after rules 6–9 and apply at most once each:

| Cap | Condition | Rationale |
| --- | --- | --- |
| **Unestimated** | `U > 0` | An unknown amount of work remains; the ratio is computed over an incomplete total. |
| **Waiting-heavy** | `W / (A + W) > 0.40` | Too much of the sprint sits in someone else's queue to claim comfort. |

Both Caps may fire, demoting two bands in total.

## Scope

| Term | Definition |
| --- | --- |
| **Sprint Baseline** | The Issue set and Estimates of the Active Sprint, snapshotted the first time Sprint Pulse observes it as active, persisted locally. |
| **Scope Delta** | Live sprint Points minus Sprint Baseline Points. Displayed; never forecast against. |

The Baseline exists solely to attribute movement. A fall in Confidence is either the Operator
falling behind or the sprint growing, and those demand different responses.

## Intents

| Intent | Meaning |
| --- | --- |
| `Start` | Move this Issue into `InProgress` |
| `Send to Review` | Move this Issue into `InReview` |
| `Mark Done` | Move this Issue into `Done` |

An Intent resolves against the transitions Jira offers for that Issue at that moment. Resolution
outcomes:

- **No legal transition reaches the target Flow State** → the button is absent. Not disabled, not
  errored: absent.
- **A legal transition exists and a legal transition returns to the current Flow State** →
  execute immediately, offer a five-second undo firing the reverse transition.
- **A legal transition exists but no return path does** → confirm once, naming the Issue key.
- **Jira unreachable** → all Intent buttons absent, identical to the no-legal-transition case.

## Status Map

Jira status strings appear here and nowhere else in the system.

| Jira status (Data Center) | Flow State |
| --- | --- |
| Backlog | `ToDo` |
| Open | `ToDo` |
| Need Info | `OnHold` |
| In Progress | `InProgress` |
| In Review | `InReview` |
| Done | `Done` |
| Cancelled | `Dropped` |

Any Jira status not appearing in the map is an **Unmapped Status**. Its Issues are excluded from
every set, surfaced prominently in the interface, and force Confidence to `Unknown` (rule 1). An
Unmapped Status is never inferred, defaulted, or bucketed by resemblance.

## Identity

The Operator is identified by the `key` and `name` returned from `/rest/api/2/myself` at
credential setup. Assignee matching is on `key`, falling back to `name`.

Jira Data Center identifies users by `name` (mutable username) and `key` (stable across renames)
— not Jira Cloud's `accountId`. Matching on the wrong field yields an empty forecast rather than
an error, which is why identity is resolved from the API and never typed by the Operator.
