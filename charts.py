"""Support charts (matplotlib/seaborn) from outputs/*.csv"""
import os, pandas as pd, numpy as np, matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt, seaborn as sns
sns.set_theme(style="whitegrid"); BASE = os.path.dirname(os.path.abspath(__file__)); OUT = os.environ.get("FD_OUT", f"{BASE}/outputs"); CH = os.environ.get("FD_CHARTS", f"{BASE}/charts"); os.makedirs(CH, exist_ok=True)
o = lambda n: pd.read_csv(f"{OUT}/{n}.csv")
# 1 cohort heatmap
c = o("c01_cohort_retention_heatmap").set_index("cohort")[["w1", "w2", "w3", "w4", "w5", "w6", "w8", "w12"]]
fig, ax = plt.subplots(figsize=(8, 10)); sns.heatmap(c, annot=True, fmt=".0f", cmap="YlGnBu", cbar_kws={"label": "% of cohort active"}, ax=ax, linewidths=.3, annot_kws={"size": 7})
ax.set_title("Weekly retention by signup month (blank = week not yet observable)"); ax.set_xlabel("weeks since signup"); fig.tight_layout(); fig.savefig(f"{CH}/01_cohort_heatmap.png", dpi=140); plt.close()
# 2 funnel + trend
f = o("f02_funnel_overall"); t = o("f01_trend_by_quarter"); fig, ax = plt.subplots(1, 2, figsize=(12, 4))
ax[0].barh(f.step[::-1], f.pct_of_signups[::-1], color="#2a9d8f"); [ax[0].text(v + 1, i, f"{v:.0f}%", va="center") for i, v in enumerate(f.pct_of_signups[::-1])]; ax[0].set_title("Activation funnel (% of signups)")
ax[1].plot(t.q, t.activation_pct, marker="o", label="activation %"); ax[1].plot(t.q, t.w4_pct, marker="o", label="week-4 retention %"); ax2 = ax[1].twinx(); ax2.bar(t.q, t.signups, alpha=.15, color="grey"); ax2.grid(False)
ax[1].set_ylim(0, 60); ax[1].legend(loc="lower right"); plt.setp(ax[1].get_xticklabels(), rotation=45, ha="right"); ax[1].set_title("Signups (bars) grew; activation and W4 stayed flat"); fig.tight_layout(); fig.savefig(f"{CH}/02_funnel_and_trend.png", dpi=140); plt.close()
# 3 aha: window scan + behaviours
w = o("a02_invite_window_scan"); b = o("a01_candidate_behaviours").sort_values("lift_pp"); fig, ax = plt.subplots(1, 2, figsize=(12, 4))
ax[0].plot(w.n_days.astype(str), w.gap_pp, marker="o", color="#e76f51"); ax[0].set_title("Week-12 retention gap: invited within N days vs not (pp)"); ax[0].set_xlabel("N days"); ax[0].axvline("3", ls="--", c="grey")
ax[1].barh(b.beh, b.lift_pp, color="#264653"); ax[1].set_title("Retention lift (pp) by first-week behaviour"); fig.tight_layout(); fig.savefig(f"{CH}/03_aha.png", dpi=140); plt.close()
# 4 forest plot exp2 by platform + overall
p = o("ab_platform"); p = p[p.experiment_id == 2]; r = o("ab_results"); r = r[(r.experiment_id == 2) & (r.metric == "activation_7d")]
rows = [("Overall", r.diff_pp.iloc[0], r.lo_pp.iloc[0], r.hi_pp.iloc[0])] + [(x.platform, x.diff_pp, x.lo_pp, x.hi_pp) for x in p.itertuples()]
fig, ax = plt.subplots(figsize=(7, 3)); [ax.errorbar(d, i, xerr=[[d - lo], [hi - d]], fmt="o", color="#e76f51" if d < 0 else "#2a9d8f", capsize=4) for i, (n, d, lo, hi) in enumerate(rows)]
ax.set_yticks(range(len(rows))); ax.set_yticklabels([x[0] for x in rows]); ax.axvline(0, c="k", lw=1); ax.set_xlabel("activation_7d lift, treatment - control (pp, 95% CI)"); ax.set_title("new_onboarding_flow: helps web, hurts iOS"); fig.tight_layout(); fig.savefig(f"{CH}/04_exp2_forest.png", dpi=140); plt.close()
# 5 novelty (exp1)
wk = o("ab_weekly"); w1 = wk[wk.experiment_id == 1]; fig, ax = plt.subplots(figsize=(7, 3.5)); ax.errorbar(w1.wk, w1.diff_pp, yerr=[w1.diff_pp - w1.lo_pp, w1.hi_pp - w1.diff_pp], marker="o", capsize=3)
ax.axhline(0, c="k", lw=1); ax.set_xlabel("week since experiment start"); ax.set_ylabel("activation lift (pp)"); ax.set_title("onboarding_checklist: lift fades (novelty)"); fig.tight_layout(); fig.savefig(f"{CH}/05_exp1_novelty.png", dpi=140); plt.close()
print("charts ok")
