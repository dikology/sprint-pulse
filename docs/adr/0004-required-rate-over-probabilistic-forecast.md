# A required-rate ratio, not a probabilistic forecast

Confidence is `Demonstrated Rate ÷ Required Rate` mapped onto named bands, not a probability of
finishing.

The stated primary outcome is a forecast the Operator can *argue with*. A ratio of two visible
numbers — what you must burn per day, what you have been burning — can be checked by hand in
seconds. A probability cannot: it can only be trusted or ignored, and an instrument you have to
trust is not an instrument.

## Considered options

**Historical velocity bands** (mean and spread over prior sprints) and **Monte Carlo simulation**
over historical throughput are both more defensible statistically. Both were rejected for the
MVP: they need history that does not exist yet, they require defining what makes a past sprint
comparable, and neither survives the "explain this number in one sentence" test.

Someone will propose Monte Carlo again. The objection is not that it is wrong — it is that its
output is not the kind of thing this product exists to show.

## Consequences

Demonstrated Rate is a **named, swappable input**, currently filled from this sprint's own
achieved rate. A historical or simulated capacity figure can be substituted later without
touching the bands, the Caps, or anything downstream — which is what keeps this decision
recoverable.

Because the current-sprint rate is undefined at the start, `Unknown` had to become a real
Confidence State rather than an error: below two elapsed Working Days, or with zero completed
Points, the app shows the Required Rate alone and declines to forecast.
