-- ============================================================================
-- STAGE 3: COHORT RETENTION + AHA MOMENT (DuckDB). Population = clean owners (table uo from 03).
-- Right-censoring rule: week-k retention is only computed for users who signed up early enough for week k to be fully observed
-- (cutoff dates below = 2025-12-31 minus (k+1) weeks). Otherwise recent cohorts look falsely bad.
-- ============================================================================

-- name: c01_cohort_retention_heatmap
-- Rows = signup month; columns = % of cohort active in week k after signup. NULL = week not yet observable.
SELECT cohort, COUNT(*) signups,
 ROUND(100.0*SUM(CASE WHEN created_at<='2025-12-17' THEN w1 END)/NULLIF(SUM(CASE WHEN created_at<='2025-12-17' THEN 1 END),0),1) w1,
 ROUND(100.0*SUM(CASE WHEN created_at<='2025-12-10' THEN w2 END)/NULLIF(SUM(CASE WHEN created_at<='2025-12-10' THEN 1 END),0),1) w2,
 ROUND(100.0*SUM(CASE WHEN created_at<='2025-12-03' THEN w3 END)/NULLIF(SUM(CASE WHEN created_at<='2025-12-03' THEN 1 END),0),1) w3,
 ROUND(100.0*SUM(CASE WHEN created_at<='2025-11-26' THEN w4 END)/NULLIF(SUM(CASE WHEN created_at<='2025-11-26' THEN 1 END),0),1) w4,
 ROUND(100.0*SUM(CASE WHEN created_at<='2025-11-19' THEN w5 END)/NULLIF(SUM(CASE WHEN created_at<='2025-11-19' THEN 1 END),0),1) w5,
 ROUND(100.0*SUM(CASE WHEN created_at<='2025-11-12' THEN w6 END)/NULLIF(SUM(CASE WHEN created_at<='2025-11-12' THEN 1 END),0),1) w6,
 ROUND(100.0*SUM(CASE WHEN created_at<='2025-10-29' THEN w8 END)/NULLIF(SUM(CASE WHEN created_at<='2025-10-29' THEN 1 END),0),1) w8,
 ROUND(100.0*SUM(CASE WHEN created_at<='2025-10-01' THEN w12 END)/NULLIF(SUM(CASE WHEN created_at<='2025-10-01' THEN 1 END),0),1) w12
FROM uo GROUP BY 1 ORDER BY 1;

-- name: c02_retention_by_activation
-- Retention curve for activated vs not-activated owners (matured for week 12 only, so every column is comparable).
SELECT activated, COUNT(*) users, ROUND(100.0*AVG(w1),1) w1, ROUND(100.0*AVG(w2),1) w2, ROUND(100.0*AVG(w4),1) w4, ROUND(100.0*AVG(w8),1) w8, ROUND(100.0*AVG(w12),1) w12
FROM uo WHERE mature_w12=1 GROUP BY 1 ORDER BY 1;

-- name: a00_aha_base
-- first_inv = seconds from signup to the owner's first teammate_invited event (NULL = never).
DROP TABLE IF EXISTS inv1;
CREATE TABLE inv1 AS SELECT user_id, MIN(sec) first_inv FROM ev WHERE event_name='teammate_invited' AND sec>=0 GROUP BY 1;
DROP TABLE IF EXISTS ab;
CREATE TABLE ab AS SELECT uo.*, i.first_inv FROM uo LEFT JOIN inv1 i USING (user_id) WHERE mature_w12=1;
SELECT COUNT(*) matured_owners, ROUND(100.0*AVG(w4),1) w4_pct, ROUND(100.0*AVG(w12),1) w12_pct FROM ab;

-- name: a01_candidate_behaviours
-- Hypothesis scan: which first-week behaviours separate retained from churned users? Same population, same outcome (week 12).
-- prevalence = share of users doing it; lift_pp = retention(with) - retention(without).
WITH f AS (SELECT user_id, w12, w4, 'invited teammate within 3d' beh, CASE WHEN first_inv < 259200 THEN 1 ELSE 0 END x FROM ab UNION ALL
 SELECT user_id, w12, w4, 'invited teammate within 7d', CASE WHEN first_inv < 604800 THEN 1 ELSE 0 END FROM ab UNION ALL
 SELECT user_id, w12, w4, 'activated (project + 3 tasks, 7d)', activated FROM ab UNION ALL
 SELECT user_id, w12, w4, 'created a project in 7d', s_project FROM ab UNION ALL
 SELECT user_id, w12, w4, '>=3 sessions in 7d', CASE WHEN sessions_7d>=3 THEN 1 ELSE 0 END FROM ab UNION ALL
 SELECT user_id, w12, w4, '>=1 comment in 7d', CASE WHEN comments_7d>=1 THEN 1 ELSE 0 END FROM ab UNION ALL
 SELECT user_id, w12, w4, '>=1 task assigned in 7d', CASE WHEN assigns_7d>=1 THEN 1 ELSE 0 END FROM ab UNION ALL
 SELECT user_id, w12, w4, 'connected integration in 7d', CASE WHEN integ_7d>=1 THEN 1 ELSE 0 END FROM ab UNION ALL
 SELECT user_id, w12, w4, '>=10 tasks completed in 7d', CASE WHEN tasks_done_7d>=10 THEN 1 ELSE 0 END FROM ab)
SELECT beh, ROUND(100.0*AVG(x),1) prevalence_pct, ROUND(100.0*SUM(CASE WHEN x=1 THEN w12 END)/SUM(x),1) w12_with, ROUND(100.0*SUM(CASE WHEN x=0 THEN w12 END)/SUM(1-x),1) w12_without,
       ROUND(100.0*SUM(CASE WHEN x=1 THEN w12 END)/SUM(x) - 100.0*SUM(CASE WHEN x=0 THEN w12 END)/SUM(1-x),1) lift_pp
FROM f GROUP BY 1 ORDER BY 5 DESC;

-- name: a02_invite_window_scan
-- Why 3 days? Scan the window: invite within N days vs not, week-12 retention gap. A sharp drop-off after day N supports "N" as the threshold.
SELECT n_days, ROUND(100.0*AVG(CASE WHEN first_inv < n_days*86400 THEN 1.0 ELSE 0 END),1) prevalence_pct,
  ROUND(100.0*SUM(CASE WHEN first_inv < n_days*86400 THEN w12 END)/SUM(CASE WHEN first_inv < n_days*86400 THEN 1 END),1) w12_invited,
  ROUND(100.0*SUM(CASE WHEN first_inv >= n_days*86400 OR first_inv IS NULL THEN w12 END)/SUM(CASE WHEN first_inv >= n_days*86400 OR first_inv IS NULL THEN 1 END),1) w12_not,
  ROUND(100.0*SUM(CASE WHEN first_inv < n_days*86400 THEN w12 END)/SUM(CASE WHEN first_inv < n_days*86400 THEN 1 END) - 100.0*SUM(CASE WHEN first_inv >= n_days*86400 OR first_inv IS NULL THEN w12 END)/SUM(CASE WHEN first_inv >= n_days*86400 OR first_inv IS NULL THEN 1 END),1) gap_pp
FROM ab, (SELECT 1 n_days UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 5 UNION ALL SELECT 7 UNION ALL SELECT 14 UNION ALL SELECT 30) w GROUP BY 1 ORDER BY 1;

-- name: a03_confounding_check_stratified
-- Invites could just mark "engaged people". Compare invited-3d vs not WITHIN strata of activation and device; if the gap persists inside every stratum
-- it is not explained by those factors (still observational: other unmeasured engagement could remain).
SELECT 'activated=' || CAST(activated AS VARCHAR) stratum, COUNT(*) users, ROUND(100.0*AVG(CASE WHEN first_inv<259200 THEN 1.0 ELSE 0 END),1) pct_invited,
  ROUND(100.0*SUM(CASE WHEN first_inv<259200 THEN w12 END)/NULLIF(SUM(CASE WHEN first_inv<259200 THEN 1 END),0),1) w12_invited,
  ROUND(100.0*SUM(CASE WHEN first_inv>=259200 OR first_inv IS NULL THEN w12 END)/SUM(CASE WHEN first_inv>=259200 OR first_inv IS NULL THEN 1 END),1) w12_not FROM ab GROUP BY 1
UNION ALL SELECT 'device=' || platform, COUNT(*), ROUND(100.0*AVG(CASE WHEN first_inv<259200 THEN 1.0 ELSE 0 END),1),
  ROUND(100.0*SUM(CASE WHEN first_inv<259200 THEN w12 END)/NULLIF(SUM(CASE WHEN first_inv<259200 THEN 1 END),0),1),
  ROUND(100.0*SUM(CASE WHEN first_inv>=259200 OR first_inv IS NULL THEN w12 END)/SUM(CASE WHEN first_inv>=259200 OR first_inv IS NULL THEN 1 END),1) FROM ab GROUP BY 1
UNION ALL SELECT 'size=' || size_band, COUNT(*), ROUND(100.0*AVG(CASE WHEN first_inv<259200 THEN 1.0 ELSE 0 END),1),
  ROUND(100.0*SUM(CASE WHEN first_inv<259200 THEN w12 END)/NULLIF(SUM(CASE WHEN first_inv<259200 THEN 1 END),0),1),
  ROUND(100.0*SUM(CASE WHEN first_inv>=259200 OR first_inv IS NULL THEN w12 END)/SUM(CASE WHEN first_inv>=259200 OR first_inv IS NULL THEN 1 END),1) FROM ab GROUP BY 1 ORDER BY 1;

-- name: a04_dose_response_invites_3d
SELECT CASE WHEN invites_3d=0 THEN '0' WHEN invites_3d=1 THEN '1' WHEN invites_3d=2 THEN '2' ELSE '3+' END invites_in_3d, COUNT(*) users, ROUND(100.0*AVG(w4),1) w4, ROUND(100.0*AVG(w12),1) w12 FROM ab GROUP BY 1 ORDER BY 1;

-- name: a05_randomised_invite_experiment_raw
-- Experiment 4 (invite_prompt) randomised owners. Randomisation breaks the confounding: if treatment raises early invites AND retention,
-- the invite->retention link has causal support. Counts feed the CI/IV calculation in stats_ab.py.
SELECT x.variant, COUNT(*) users, SUM(CASE WHEN u.invites_3d>=1 THEN 1 ELSE 0 END) invited_3d, SUM(u.mature_w4) mature_w4, SUM(CASE WHEN u.mature_w4=1 THEN u.w4 ELSE 0 END) w4_retained,
       SUM(u.mature_w12) mature_w12, SUM(CASE WHEN u.mature_w12=1 THEN u.w12 ELSE 0 END) w12_retained
FROM experiment_assignments x JOIN uf u ON u.user_id=x.unit_id WHERE x.experiment_id=4 AND u.is_test=0 AND u.is_dup=0 GROUP BY 1 ORDER BY 1;
