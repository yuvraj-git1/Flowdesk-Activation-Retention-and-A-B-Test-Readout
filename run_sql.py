"""Run SQL files made of `-- name: x` blocks on DuckDB; each block's last SELECT is saved to <outputs>/x.csv.
usage: python run_sql.py sql/01_profiling.sql sql/02_clean_base.sql ...   (run all five in ONE call, in order: later files reuse tables built by earlier ones)
Data: FD_DATA=<folder with the 5 CSVs>; default data/csv/ if present, else data/sample/ (1,000-row demo; results differ, written to outputs_sample/ so committed outputs are not overwritten).
Env: FD_OUT overrides the output folder. Paths resolve relative to this file, so it works from any directory."""
import os, re, sys, time, duckdb, pandas as pd
BASE = os.path.dirname(os.path.abspath(__file__))
TABLES = ["accounts", "users", "events", "experiments", "experiment_assignments"]
full = os.path.join(BASE, "data", "csv")
DATA = os.environ.get("FD_DATA") or (full if os.path.exists(os.path.join(full, "events.csv")) else os.path.join(BASE, "data", "sample"))
SAMPLE = os.path.abspath(DATA) == os.path.abspath(os.path.join(BASE, "data", "sample"))
OUT = os.environ.get("FD_OUT") or os.path.join(BASE, "outputs_sample" if SAMPLE else "outputs")
os.makedirs(OUT, exist_ok=True)
con = duckdb.connect()   # in-memory; tables built by one SQL file are visible to the next within the same call
for t in TABLES:
    con.execute(f"create or replace view {t} as select * from read_csv_auto('{DATA}/{t}.csv', header=true, sample_size=-1)")
def main(path, show):
    blocks = re.split(r"^-- name:\s*(\w+)\s*$", open(path).read(), flags=re.M)
    for name, sql in zip(blocks[1::2], blocks[2::2]):
        stmts = [x.strip() for x in re.split(r";\s*\n", sql.strip().rstrip(";") + "\n") if re.search(r"(?i)\b(select|create|drop)\b", x)]
        for st in stmts[:-1]: con.execute(st)
        last = stmts[-1]; t0 = time.time()
        if re.match(r"(?i)\s*(create|drop)", last): con.execute(last); print(f"== {name}: ok [{time.time()-t0:.0f}s]"); continue
        d = con.execute(last).df(); d.to_csv(f"{OUT}/{name}.csv", index=False); print(f"== {name} ({len(d)} rows) [{time.time()-t0:.0f}s]\n{d.head(show).to_string(index=False)}")
if __name__ == "__main__":
    print(f"data: {DATA}\noutputs: {OUT}" + ("\n(SAMPLE data: demo only; see README to build the full dataset)" if SAMPLE else ""))
    pd.set_option("display.width", 220, "display.max_columns", 30)
    for p in sys.argv[1:]: main(p, int(os.environ.get("SHOW", 6)))
