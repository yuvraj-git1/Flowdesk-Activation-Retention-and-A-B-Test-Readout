# Tableau spec: "Activation & Retention" (data: tableau/*.csv, one connection each)

**Sheet 1 KPI strip:** Signups (`f01`), Activation %, Week-4 retention %, Invited-in-3d % (latest quarter vs prior year). Quarter filter.
**Sheet 2 Funnel (`f02`):** horizontal bars, `pct_of_signups`; tooltip step_conv. **Dashboard action:** click a step -> filter sheets 3-4 (parameter `p_cut` = channel / device / size selects `f03`/`f04`/`f05` via a dimension-switch calculated field `CASE [p_cut] WHEN 'channel' THEN [seg] ...` if you union the three files; otherwise place three small multiples).
**Sheet 3 Cohort heatmap (`c01`):** pivot to long (Pivot columns w1..w12 -> `week`, `retention`). Rows = cohort month, columns = week, colour = retention % (sequential teal, 0-80), labels on. Blank cells stay blank (censored).
**Sheet 4 Aha (`a01`, `a02`, `a04`):** bar of lift_pp by behaviour; line of gap_pp by invite-window N; bars of W12 by number of invites.
**Sheet 5 A/B readout (`ab_results`, `ab_platform`, `ab_weekly`, `ab_srm`):** forest plot (diff_pp with lo_pp/hi_pp as error bars; zero reference line), colour by sign; platform small multiples for `new_onboarding_flow`; weekly lift line for `onboarding_checklist`; SRM table with `srm_warning` highlighted.
**Layout (1400x900):** KPI strip top; funnel + heatmap middle; aha bottom-left; A/B tabs on a second dashboard.
**Calculated fields:** `Lift CI label = STR(ROUND([diff_pp],1)) + " [" + STR(ROUND([lo_pp],1)) + ", " + STR(ROUND([hi_pp],1)) + "]"`; `Significant = [lo_pp]>0 OR [hi_pp]<0`.
**Notes:** never show retention for unobservable weeks; label the Android Oct 14-Nov 3 2024 window ("duplicate task events removed"). Extracts refresh by re-running `sql/` then `stats_ab.py`.
