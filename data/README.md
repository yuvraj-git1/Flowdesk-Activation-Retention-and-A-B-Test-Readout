# Data

Five synthetic tables from the Flowdesk data world (fixed seed; no real people or third-party data, so no licence restrictions; emails are placeholders like `user1@nan`):
accounts, users, events, experiments, experiment_assignments. Column meanings: `docs/data_dictionary.md`.

- `sample/` first 1,000 rows of each (7 rows for experiments), for a quick look and a code smoke test.
- The full events table is ~366 MB (3.45M rows), too big for git, so it is not committed. Build it:
  1. Get the Flowdesk generator (the "Flowdesk Data Foundation" repo, `pip install numpy pandas`).
  2. `python run_all.py` (about 1 min; fixed seed, so output is deterministic).
  3. Copy `accounts.csv users.csv events.csv experiments.csv experiment_assignments.csv` from its `data/csv/` into this repo's `data/csv/`.
  Do not copy the other files in `data/csv/`; `answer_key.csv`, `planted_rows.csv` and `true_*.csv` are the generator's answer key.
- Alternative: point `FD_DATA=/path/to/csvs` at any folder holding those five files.
