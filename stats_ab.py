"""A/B statistics from the SQL count tables (outputs/ab0*.csv). scipy + numpy only.
statsmodels equivalents (if you want to cross-check): proportions_ztest, confint_proportions_2indep, multipletests(method='holm')."""
import os, numpy as np, pandas as pd
from scipy import stats
Z = stats.norm.ppf(0.975)
OUT = os.environ.get("FD_OUT", os.path.join(os.path.dirname(os.path.abspath(__file__)), "outputs"))   # same folder run_sql.py wrote to
o = lambda n: pd.read_csv(f"{OUT}/{n}.csv")
EXP = o("p09_experiment_assignment_profile").set_index("experiment_id").name.to_dict()
METRIC = {1: ("activated", "n"), 2: ("activated", "n"), 3: ("paid_30d", "n"), 4: ("invited_3d", "n"), 5: ("paid_30d", "n"), 6: ("activated", "n")}
LABEL = {"activated": "activation_7d", "paid_30d": "paid_30d", "invited_3d": "invited_3d"}

def two_prop(x0, n0, x1, n1):
    """control (x0,n0) vs treatment (x1,n1): diff, unpooled-Wald 95% CI, pooled z-test p. Why: unpooled SE for the CI, pooled SE under H0 for the test."""
    p0, p1 = x0 / n0, x1 / n1; d = p1 - p0; se = np.sqrt(p0 * (1 - p0) / n0 + p1 * (1 - p1) / n1)
    pp = (x0 + x1) / (n0 + n1); se0 = np.sqrt(pp * (1 - pp) * (1 / n0 + 1 / n1)); p = 2 * (1 - stats.norm.cdf(abs(d / se0))) if se0 > 0 else 1.0
    return dict(p_control=p0, p_treat=p1, diff_pp=100 * d, lo_pp=100 * (d - Z * se), hi_pp=100 * (d + Z * se), rel_lift_pct=100 * d / p0 if p0 > 0 else np.nan, p_value=p, se=se)

def mde(p, n_each, power=0.8):
    """Minimum detectable absolute effect (pp) at alpha=.05 for equal arms."""
    return 100 * (Z + stats.norm.ppf(power)) * np.sqrt(2 * p * (1 - p) / n_each)

A = o("ab01_arm_counts_and_outcomes"); rows = []; srm = []
for e, g in A.groupby("experiment_id"):
    c, t = g[g.variant == "control"].iloc[0], g[g.variant == "treatment"].iloc[0]
    # SRM: chi-square goodness-of-fit vs planned 50/50. p < 0.001 = assignment is broken, effect estimates are not trustworthy.
    chi, p = stats.chisquare([c.n, t.n], [(c.n + t.n) / 2] * 2)
    srm.append(dict(experiment_id=e, name=EXP[e], n_control=c.n, n_treatment=t.n, pct_treatment=100 * t.n / (c.n + t.n), chi2=chi, p_value=p, srm_flag=p < 0.001, srm_warning=p < 0.05))
    m, _ = METRIC[e]; r = two_prop(c[m], c.n, t[m], t.n); r.update(experiment_id=e, name=EXP[e], metric=LABEL[m], n_control=c.n, n_treatment=t.n, mde_pp_80power=mde(r["p_control"], min(c.n, t.n)))
    rows.append(r)
    if e in (1, 2, 4, 6):   # guardrail: week-4 retention
        g4 = two_prop(c.w4_ret, c.n_w4, t.w4_ret, t.n_w4); g4.update(experiment_id=e, name=EXP[e], metric="w4_retention_guardrail", n_control=c.n_w4, n_treatment=t.n_w4, mde_pp_80power=mde(g4["p_control"], min(c.n_w4, t.n_w4))); rows.append(g4)
    if e == 4:
        g12 = two_prop(c.w12_ret, c.n_w12, t.w12_ret, t.n_w12); g12.update(experiment_id=e, name=EXP[e], metric="w12_retention", n_control=c.n_w12, n_treatment=t.n_w12, mde_pp_80power=mde(g12["p_control"], min(c.n_w12, t.n_w12))); rows.append(g12)
res = pd.DataFrame(rows).round(4); sr = pd.DataFrame(srm).round(5); res.to_csv(f"{OUT}/ab_results.csv", index=False); sr.to_csv(f"{OUT}/ab_srm.csv", index=False)
print(sr[["experiment_id", "name", "n_control", "n_treatment", "pct_treatment", "p_value", "srm_flag"]].to_string(index=False)); print()
print(res[["experiment_id", "name", "metric", "p_control", "p_treat", "diff_pp", "lo_pp", "hi_pp", "p_value", "mde_pp_80power"]].to_string(index=False))

# ---- Platform segments (+ Holm correction over the 3 platforms, + heterogeneity Q test)
P = o("ab02_arm_counts_by_platform"); seg = []
for e, g in P.groupby("experiment_id"):
    m = METRIC[e][0]; sub = []
    for pl, h in g.groupby("platform"):
        c, t = h[h.variant == "control"].iloc[0], h[h.variant == "treatment"].iloc[0]; r = two_prop(c[m], c.n, t[m], t.n); r.update(experiment_id=e, name=EXP[e], platform=pl, n_control=c.n, n_treatment=t.n); sub.append(r)
    ps = np.array([r["p_value"] for r in sub]); order = np.argsort(ps); holm = np.empty(3)   # Holm: sort p, multiply by (k - rank), enforce monotone
    run = 0
    for rank, i in enumerate(order): run = max(run, min(1, ps[i] * (3 - rank))); holm[i] = run
    d = np.array([r["diff_pp"] for r in sub]) / 100; w = 1 / np.array([r["se"] ** 2 for r in sub]); dbar = (w * d).sum() / w.sum(); Q = (w * (d - dbar) ** 2).sum(); pQ = 1 - stats.chi2.cdf(Q, 2)
    for r, h in zip(sub, holm): r.update(p_holm=h, het_Q=Q, het_p=pQ, metric=LABEL[m]); seg.append(r)
sg = pd.DataFrame(seg).round(4); sg.to_csv(f"{OUT}/ab_platform.csv", index=False)
print(); print(sg[["experiment_id", "name", "platform", "p_control", "p_treat", "diff_pp", "lo_pp", "hi_pp", "p_holm", "het_p"]].to_string(index=False))

# ---- Novelty: effect by week since start + weighted slope (pp per week)
W = o("ab04_effect_by_week_since_start"); wk = []
for e, g in W.groupby("experiment_id"):
    m = {"activated": "activated", "paid_30d": "paid_30d", "invited_3d": "invited_3d"}[METRIC[e][0]]
    for k, h in g.groupby("wk"):
        c, t = h[h.variant == "control"], h[h.variant == "treatment"]
        if len(c) and len(t) and c.n.iloc[0] >= 40 and t.n.iloc[0] >= 40:
            r = two_prop(c[m].iloc[0], c.n.iloc[0], t[m].iloc[0], t.n.iloc[0]); r.update(experiment_id=e, name=EXP[e], wk=k, n=c.n.iloc[0] + t.n.iloc[0]); wk.append(r)
wd = pd.DataFrame(wk); sl = []
for e, g in wd.groupby("experiment_id"):
    x = g.wk.values.astype(float); y = g.diff_pp.values; w_ = 1 / (g.se.values * 100) ** 2; X = np.c_[np.ones_like(x), x]; cov = np.linalg.inv(X.T @ (w_[:, None] * X)); b = cov @ X.T @ (w_ * y)
    sl.append(dict(experiment_id=e, name=EXP[e], slope_pp_per_week=b[1], slope_se=np.sqrt(cov[1, 1]), slope_p=2 * (1 - stats.norm.cdf(abs(b[1] / np.sqrt(cov[1, 1])))), first2wk_pp=g[g.wk <= 1].diff_pp.mean(), last2wk_pp=g[g.wk >= g.wk.max() - 1].diff_pp.mean()))
sl = pd.DataFrame(sl).round(4); wd.round(4).to_csv(f"{OUT}/ab_weekly.csv", index=False); sl.to_csv(f"{OUT}/ab_novelty.csv", index=False); print(); print(sl.to_string(index=False))

# ---- Exp 4 (randomised invite prompt): Wald/IV estimate of invite -> retention = ITT_retention / ITT_invite, delta-method CI
R = o("a05_randomised_invite_experiment_raw"); c, t = R[R.variant == "control"].iloc[0], R[R.variant == "treatment"].iloc[0]
for lab, xc, nc, xt, nt in (("w4", c.w4_retained, c.mature_w4, t.w4_retained, t.mature_w4), ("w12", c.w12_retained, c.mature_w12, t.w12_retained, t.mature_w12)):
    fs = two_prop(c.invited_3d, c.users, t.invited_3d, t.users); rf = two_prop(xc, nc, xt, nt); ratio = 100 * rf["diff_pp"] / fs["diff_pp"]   # pp of retention per +100pp of invite rate (i.e. effect of one early invite)
    se = 100 * np.sqrt((rf["se"] * 100 / fs["diff_pp"]) ** 2 + (rf["diff_pp"] * fs["se"] * 100 / fs["diff_pp"] ** 2) ** 2)
    print(f"\nExp4 IV ({lab}): first-stage invite lift {fs['diff_pp']:.2f}pp (p={fs['p_value']:.3f}); reduced-form {lab} lift {rf['diff_pp']:.2f}pp (p={rf['p_value']:.3f}); implied effect of an early invite = {ratio:.1f}pp (95% CI {ratio-Z*se:.1f} to {ratio+Z*se:.1f})")
    pd.DataFrame([dict(outcome=lab, first_stage_pp=fs["diff_pp"], reduced_form_pp=rf["diff_pp"], implied_invite_effect_pp=ratio, lo=ratio - Z * se, hi=ratio + Z * se)]).round(3).to_csv(f"{OUT}/ab_iv_{lab}.csv", index=False)

# ---- Exp 2 decision table: web vs mobile pooled, activation AND week-4 retention guardrail by platform
g = P[P.experiment_id == 2].copy(); g["grp"] = np.where(g.platform == "web", "web", "mobile (ios+android)"); out = []
for grp, h in g.groupby("grp"):
    c, t = h[h.variant == "control"].sum(numeric_only=True), h[h.variant == "treatment"].sum(numeric_only=True)
    for lab, xc, nc, xt, nt in (("activation_7d", c.activated, c.n, t.activated, t.n), ("w4_retention", c.w4_ret, c.n_w4, t.w4_ret, t.n_w4)):
        r = two_prop(xc, nc, xt, nt); r.update(segment=grp, metric=lab, n_control=nc, n_treatment=nt); out.append(r)
for pl, h in g.groupby("platform"):
    c, t = h[h.variant == "control"].iloc[0], h[h.variant == "treatment"].iloc[0]; r = two_prop(c.w4_ret, c.n_w4, t.w4_ret, t.n_w4); r.update(segment=pl, metric="w4_retention", n_control=c.n_w4, n_treatment=t.n_w4); out.append(r)
d2 = pd.DataFrame(out).round(4); d2.to_csv(f"{OUT}/ab_exp2_decision.csv", index=False); print(); print(d2[["segment", "metric", "p_control", "p_treat", "diff_pp", "lo_pp", "hi_pp", "p_value"]].to_string(index=False))
