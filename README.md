# Flowdesk Activation, Retention & A/B Test Readout

## Findings (read first)
- **Signups doubled; activation (~42%) and week-4 retention (~38%) stayed flat for 12 quarters.** Proven.
- **Biggest drop:** 32% of signups never create a project in 7 days. Review-site signups activate at 32% vs 46-49% for referral/partner.
- **Aha moment:** inviting a teammate within 3 days -> week-12 retention 49% vs 19%. Peaks at a 3-day window and survives stratification; a randomised invite test supports it but is underpowered (suggestive causation).
- **Ship call for `new_onboarding_flow`: don't ship to everyone, iterate.** Overall +2.1pp is inconclusive; it hides web **+8.6pp** and iOS **-10.6pp** (heterogeneity p<0.0001). Ship web-only with a holdback; fix mobile first.
- **Data traps found:** iOS timestamps are local time; Android 4.2.1 double-counted task completions (+6.4pp fake activation for one cohort); 2.4% duplicate signups; a novelty effect in `onboarding_checklist`; an SRM warning in `pricing_page_redesign`.
Report: [`docs/pm_report.md`](docs/pm_report.md).

## Folder structure
```
sql/            01_profiling | 02_clean_base | 03_metric_tree_funnel | 04_cohorts_aha | 05_ab_tests   (commented DuckDB SQL)
stats_ab.py     SRM, CIs, Holm, novelty slope, IV (scipy/numpy)      charts.py   PNGs from outputs/
run_sql.py      DuckDB runner (writes outputs/)
data/           data/sample = first 1,000 rows of the 5 tables (demo only); data/csv = full dataset you generate (git-ignored), see data/README.md
outputs/        query results as CSV    tableau/   extracts for the dashboard    charts/   PNGs    docs/   metric tree, dashboard spec, PM report
```

## How to run
```
git clone <repo-url> flowdesk-p2 && cd flowdesk-p2
python -m venv .venv && source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 1. build the full dataset once (see data/README.md): generate Flowdesk, copy 5 CSVs into data/csv/
# 2. run the pipeline (~1 min). Run all five SQL files in ONE call, in order: later files reuse tables built earlier.
python run_sql.py sql/01_profiling.sql sql/02_clean_base.sql sql/03_metric_tree_funnel.sql sql/04_cohorts_aha.sql sql/05_ab_tests.sql
python stats_ab.py      # A/B statistics -> outputs/ab_*.csv
python charts.py        # -> charts/*.png
```
Works from any directory (paths resolve relative to the scripts). Use data elsewhere with `FD_DATA=/path/to/csvs`; redirect results with `FD_OUT=/path` (set it for `stats_ab.py` and `charts.py` too).
Without the full data the runner falls back to `data/sample/` and writes to `outputs_sample/` (does not touch committed outputs). Sample numbers are meaningless for findings; it only proves the code runs.
Plain DuckDB CLI is not supported here: files rely on `-- name:` blocks parsed by `run_sql.py`.

**Verification:** run end to end on Python 3.13 / DuckDB 2.0 / pandas 3.0 / scipy on a freshly generated dataset (seed fixed). All 45 `outputs/*.csv` reproduce the committed files (identical values; only row order of a few un-sorted results can differ). Docs quote the committed outputs.

Method: owners only (one per signup), excluding test and duplicate accounts; activation = project + >=3 tasks in 7 days; week-k retention only for fully observable cohorts; ITT analysis for tests.
