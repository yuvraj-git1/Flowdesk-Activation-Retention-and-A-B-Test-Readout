# Metric tree

**North Star: Activated-and-retained signups per month**, i.e. new owners who (1) activate in 7 days and (2) are still active in week 4. It combines volume, quality and stickiness; signups alone grew 2x while this stayed per-signup flat.

| Level | Metric | Definition (SQL) | Current |
|---|---|---|---|
| Input 1 | Signup volume | clean owners per month (`uo`) | ~1.3K/month |
| Input 2 | Project-creation rate | project_created in 7d | 67.9% |
| Input 3 | Task completion depth | >=3 task_completed in 7d | 42.0% (= activation) |
| Input 4 | Early collaboration (aha) | teammate_invited in 3d | 27.6% |
| Output | Week-4 retention | any event in days 28-34 | 37.9% |
| Guardrail | Week-12 retention | days 84-90 | 27.5% |
| Guardrail | Mobile activation | iOS/Android activation vs web | 42.9/40.3 vs 42.2% |
| Guardrail | Data quality | duplicate task events, test/dup signups excluded | see issue log |

Definitions: *activation* = >=1 project_created AND >=3 task_completed within 7 days of signup; population = account owners excluding internal test and duplicate accounts; week-k retention only for cohorts old enough to observe week k.
