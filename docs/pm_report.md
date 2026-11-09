# Flowdesk: Activation, Retention & Onboarding Test Readout

**Decision: do NOT ship `new_onboarding_flow` to everyone. Iterate: roll out to web only (with a holdback) and fix iOS/Android first.**

## What I found
| # | Finding | Evidence | Status |
|---|---|---|---|
| 1 | Signups doubled (1.9K -> 4.1K/quarter) but activation (41-43%) and week-4 retention (37-38%) did not move in 12 quarters | `f01` | **Proven** |
| 2 | Biggest losses: 32% never create a project in 7 days; of those with a task done, 29% stop short of 3 tasks (activation = 42.0%) | `f02` | **Proven** |
| 3 | Channel matters most: activation 49% (partner) / 46% (referral) vs 32% (review_site, also lowest week-4 at 29%). Android lags (40% vs 43% iOS). Company size barely matters | `f03-f05` | **Proven** (channel); size effect on W4 for 1000+ **suggestive** (n=1.2K) |
| 4 | Inviting a teammate within 3 days is the strongest actionable predictor: week-12 retention 49% vs 19% (+30pp). The gap peaks at a 3-day window, holds inside every activation/device/size stratum, and the first invite does almost all the work | `a01-a04` | **Proven** association; **suggestive** causation |
| 5 | The randomised invite-prompt test raised early invites +6.9pp (p=0.002) and week-12 retention +2.5pp (n.s.); implied effect of an early invite ~36pp but CI is -30 to +102 | `ab_iv_w12` | First stage **proven**; causal size **suggestive** (underpowered) |
| 6 | Activation is activated-vs-not retention: week-12 36% vs 22% (+14pp), much smaller than the invite gap | `c02` | **Proven** |

## A/B readout: `new_onboarding_flow` (4,841 users, Feb 5-Mar 18 2024)
- **Sanity checks passed:** split 49.1% treatment (SRM p=0.21), no overlap with other tests, assignments within signup+60s, balanced platform mix, 3% never exposed (analysed as assigned = ITT).
- **Overall:** activation +2.1pp (95% CI -0.7 to +4.9, p=0.14): **inconclusive** (the test could only detect >=4.1pp).
- **The overall number hides opposite effects (Holm-adjusted, heterogeneity p<0.0001):** web **+8.6pp** (+5.0 to +12.2), iOS **-10.6pp** (-16.6 to -4.7), Android -3.6pp (-10.2 to +2.9, n.s.). Pooled mobile -7.5pp (-11.9 to -3.1).
- **Guardrail, week-4 retention:** web +1.9pp (n.s.), mobile -3.5pp (n.s., p=0.10): no evidence of web harm, a worrying signal on mobile.
- **No novelty effect** (weekly lift slope +0.3pp/week, p=0.72).
- **Call: iterate.** Ship to web (60% of users) behind a 10% holdback; hold back iOS and Android until the mobile flow is fixed and re-tested with >=2,000 users per arm.

## Other experiments (same checks)
| Test | Result | Caveat |
|---|---|---|
| onboarding_checklist | +5.0pp activation (p=0.003) but **novelty**: +15.6pp in weeks 0-1 vs +0.6pp in the last two weeks (slope -3.8pp/week, p=0.0001); week-4 retention -2.7pp (n.s.) | Do not ship on the headline: true steady-state effect looks ~0. **Proven** novelty |
| pricing_page_redesign | +1.4pp paid conversion (n.s.) | **SRM warning:** 47.1% treatment (p=0.02, below the strict 0.001 bar but low power at n=1.6K): treat result as untrustworthy |
| invite_prompt | invites +6.9pp, web +10.6pp (Holm p<0.001) | Mobile effect n.s. |
| annual_discount_banner | n.s. | annual-mix metric needs the billing table (not in this dataset) |
| dark_mode_default | n.s. | null result |

## Data issues that would have changed the answers
| Issue | Impact | Status |
|---|---|---|
| iOS `event_ts` is device-local time (offset matches each account's timezone) | shifts 7-day windows by up to +10h; corrected to UTC | **Proven** |
| Android v4.2.1 double-fires `task_completed` (Oct 14-Nov 3 2024; 2,364 duplicate rows) | activation 51.2% raw vs 44.8% corrected for that cohort (+6.4pp) | **Proven** |
| 796 duplicate signups (same domain within 30 days) + 40 internal test accounts | removed; activation moves only -0.14pp | **Proven** |
| 46 channel labels | mapped to 9; 0 unmapped | **Proven** |
| 'Any activity in 7d' = 100% (every signup fires a session) | funnel step carries no information | **Proven**; noise |
| ~2% null app_version, 82 events slightly before signup after tz fix | immaterial | Natural noise |

## Recommendations
1. Push the aha: prompt a teammate invite in the first session (target invited-3d from 28% upward); evaluate with the randomised design already used.
2. Fix the project-creation drop (32% never create one) and the review_site/paid_social quality gap before buying more of that traffic.
3. Redesign the mobile onboarding flow; re-test with enough users to detect a 3pp effect.
4. Add pipeline checks: dedupe task events, store UTC for all clients, SRM alert on every test.
**Limits:** observational links (4, 6) are not causal; segment tests used Holm correction but are exploratory; week-12 = any activity in days 84-90.
