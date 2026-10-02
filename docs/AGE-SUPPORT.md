# Age support: audit and review evidence

Base: `f52af402255b2dbc35a39ffb6c5d161baf64c1b9`, verified against remote
`main` on 2026-10-02. Work is isolated on `codex/mina-older-child-20261002`
in `/private/tmp/mina-older-child-20261002`. The main checkout and existing
release/physical-check evidence are preserved.

Age-specific guidance covers **birth up to the third birthday**. Logging,
sharing, timers, history, search and export continue afterward, with an explicit
“3 years & beyond” guide and no automatic age-specific targets. This range
extends the existing 24-month growth tables and two-year care schedule across
both toddler years, including the AAP 30-month screening and three-year visit.
It does not extend the growth tables or introduce a new medical schema.

## Findings and changes

| Existing assumption | Change |
| --- | --- |
| Month 4 covers days 91–365 and is the fallback for every older age | Keep the original newborn stages and milestone labels; add 6–8, 9–11, 12–17, 18–23, 24–29 and 30–35-month stages. App, widgets, Siri and Ask use calendar anniversaries from the stored birthday. |
| Weight-based milk totals, five-hour feed-gap targets and newborn diaper quotas persist forever | Stop these automatic defaults at six calendar months. Personal targets stay saved. Sleep ranges continue until the third birthday; later logging remains available. |
| Nap estimate remains 105 minutes for every older age | Stop the newborn nap-window estimate at six months. Feed predictions for older children require sufficient logged intervals. |
| Solid foods save food/allergen metadata but never enter day totals | Add separate food-entry totals to Today, Trends, weekly digest, Siri status, Ask context and the PDF report. Milk totals retain their original meaning. Food logging is always accessible, including after birthday corrections. |
| Care checklist stops at two years; birthday edits do not refresh reminders | Add 30-month and three-year visits. Refresh care reminders when the observed birthday changes, including edits received through the shared model. Keep completion history. |
| Growth months use days / 30.4375, which can exclude an exact second birthday | Use calendar anniversaries for fractional months. Keep the 24-month table limit; exclude pre-birth measurements. Increase manual growth-entry bounds for toddlers. |
| Ages keep counting months indefinitely | Use years and remaining months after the first birthday, with leap-day and end-of-month handling. |
| Guide assumes milestone labels are unique | Tolerate duplicate labels from existing family history rather than crashing. Do not rename newborn milestone labels. |
| Calendar quick-jump menu shows 24 months | No retention limit: existing arrows reach earlier months; History and export already include every entry. |

No Core Data attributes, CloudKit schema, sharing relationships, production
settings, release versions or public website are changed.

## Sources checked on 2026-10-02

New guidance describes logging routines and sourced reference ranges. Milestones
are dated memories, not a screening tool or a deadline imposed by Mina.

- [CDC feeding routines](https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/how-much-and-how-often-to-feed.html): milk remains the main nutrition at 6–12 months; meals and snacks join the routine.
- CDC checklists: [6 months](https://www.cdc.gov/act-early/milestones/6-months.html), [9 months](https://www.cdc.gov/act-early/milestones/9-months.html), [one year](https://www.cdc.gov/act-early/milestones/1-year.html), [two years](https://www.cdc.gov/act-early/milestones/2-years.html), [30 months](https://www.cdc.gov/act-early/milestones/30-months.html). New milestone text is paraphrased and limited to examples. The 18-month stage links families to the checklist rather than inventing milestone claims.
- [AASM sleep duration](https://aasm.org/recharge-with-sleep-pediatric-sleep-recommendations-promoting-optimal-health/): 12–16 hours including naps at 4–12 months; 11–14 at ages one and two.
- [AAP periodicity schedule](https://downloads.aap.org/AAP/PDF/periodicity_schedule.pdf): the 30-month and three-year visits were verified visually on page 1; developmental screening at 30 months.
- [AAP HealthyChildren breathing guidance](https://www.healthychildren.org/English/tips-tools/symptom-checker/IFrame/Pages/symptomviewer.aspx?symptom=Breathing+Trouble) and [Nationwide Children's urgent symptoms](https://www.nationwidechildrens.org/conditions/bronchiolitis): urgent breathing/colour/waking concerns.

Existing newborn content and clinician-specific plans remain in place. This is
an age-support change, not a complete medical-content audit.

## Validation completed

- `python3 scripts/test-age-core.py`: **8 XCTest cases passed, 0 failures**, native
  macOS Foundation only. Compiles the actual Guidance, Predictor and Goals sources,
  with extracted Foundation value types and isolated preferences. Covers calendar
  anniversaries, leap/month-end birthdays, DST, future/missing birthdays, exact
  24-month calculation, year labels, older-child defaults, persisted personal
  targets and prediction cutoffs. No iOS SDK or simulator is used.
- `xcodegen generate`: project and focused `AgeSupport` scheme generated.
- `swiftc -frontend -parse` on changed Swift sources: syntax check passed. This is
  not an iOS type check or runtime test.
- `git diff --check`: passed.

Native test output is retained at
`/Users/squidbot/Projects/mina/.dd-age-core-evidence-20261002/foundation-tests.log`.

## Focused iOS run pending integration

`python3 scripts/test-age-ios.py` stops before acquiring a slot or starting Xcode:
**18.92 GiB free**, below the owner-required **20 GiB**. Integrator/conductor
hand-offs rejected stale conversation targets; NAS coordination was queued.
No SDK build, simulator test or accessibility screenshot is claimed as passed.

After the integrator coordinates capacity and the Mini lane, run:

```sh
xcodegen generate
python3 scripts/test-age-ios.py
```

The script checks free space and concurrent Xcode before and inside the shared
`mini-sim-slot.sh run` lane, verifies its slot holder, uses serial tests, caps each
test at 180 seconds and the run at 15 minutes, and preserves a fresh result bundle
and log under the main checkout's `.dd-age-support-20261002`. It refuses to overwrite
an existing run directory. It cannot build on Linux.

Its exact selected tests are:

```text
MinaTests/AgeCoreTests (8)
MinaTests/AgePersistenceTests (4)
MinaTests/GuidanceTests (2)
MinaTests/PredictorTests (3)
MinaTests/GoalsTests (1)
MinaTests/WeeklyDigestTests (1)
MinaTests/UnitTests/testCareScheduleUsesCalendarDates
MinaTests/UnitTests/testWHOStandardsReturnThePublishedMedian
MinaUITests/AgeSupportUITests (1)
```

The four persistence tests cover SQLite reopen after a corrected birthday while
retaining two-parent/sibling history, food/milk separation over a DST boundary and
backup import, growth/age bounds, and reminder dates after birthday corrections.
The UI test exercises selecting an older stage and reading/tapping a toddler care
row at accessibility XXXL text size, including its spoken value and minimum tap
height, and retains a screenshot. These **22 iOS tests have not run**.

Production schema deployment and photo/sync/widget/partner-alert/Watch physical
checks remain open. No production schema edits, direct phone install, public
submission, release upload, merge, deployment or Hook restart was performed.

## Local review hand-off

Implementation commit: `dbeea4bcda53c727245c6569c4d9bc7f3ef8bda2`.
The feature branch is local. Automatic approval review rejected its remote push
because pushing publishes repository contents and the brief prohibits publishing.
No remote branch or PR was created. Draft PR text is retained in the main
checkout's `.dd-age-core-evidence-20261002/draft-pr.md` for integration review.
`dispatch_report` identifies the repository as context and explicitly reports
local-only evidence; that repository URL is not a live PR.
