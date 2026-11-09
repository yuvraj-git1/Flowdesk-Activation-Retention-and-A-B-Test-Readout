-- ============================================================================
-- STAGE 4: A/B TESTS (DuckDB). SQL produces the per-arm COUNTS; stats_ab.py turns them into SRM tests, CIs and p-values.
-- Analysis principle: ITT = analyse everyone ASSIGNED (not only those exposed), otherwise exposure selection can bias the result.
-- User-unit experiments (1,2,4,6): outcomes from uf. Account-unit experiments (3,5): outcome = paid within 30 days of signup (accounts.first_paid_at).
-- ============================================================================

-- name: ab00_assignment_base
DROP TABLE IF EXISTS xa;
CREATE TABLE xa AS
SELECT x.experiment_id, x.variant, x.unit_id, x.assigned_at, x.platform, x.first_exposed_at,
  (date_diff('day', e.start_date, x.assigned_at) - (date_diff('day', e.start_date, x.assigned_at) % 7)) / 7 wk,  -- week since experiment start (0-based)
  CASE WHEN e.unit_type='user' THEN u.created_at ELSE a.created_at END signup_at,
  COALESCE(CASE WHEN e.unit_type='user' THEN u.size_band ELSE d.size_band END, 'NA') size_band,
  COALESCE(CASE WHEN e.unit_type='user' THEN u.channel ELSE d.channel END, 'NA') channel,
  CASE WHEN e.unit_type='user' THEN u.is_test ELSE d.is_test END is_test, CASE WHEN e.unit_type='user' THEN u.is_dup ELSE d.is_dup END is_dup,
  u.projects_7d, u.tasks_done_7d, u.invites_3d, u.w4, u.mature_w4, u.w12, u.mature_w12,
  CASE WHEN a.first_paid_at IS NOT NULL AND date_diff('second', a.created_at, a.first_paid_at) <= 2592000 THEN 1 ELSE 0 END paid_30d,
  CASE WHEN a.created_at <= '2025-11-30' THEN 1 ELSE 0 END mature_paid
FROM experiment_assignments x JOIN experiments e USING (experiment_id)
LEFT JOIN uf u ON e.unit_type='user' AND u.user_id=x.unit_id
LEFT JOIN accounts a ON (e.unit_type='account' AND a.account_id=x.unit_id)
LEFT JOIN acct_dim d ON e.unit_type='account' AND d.account_id=x.unit_id;
SELECT experiment_id, COUNT(*) n, SUM(CASE WHEN signup_at IS NULL THEN 1 ELSE 0 END) unmatched FROM xa GROUP BY 1 ORDER BY 1;

-- name: ab01_arm_counts_and_outcomes
-- One row per experiment x variant: size, never-exposed, primary-metric successes and guardrail (week-4 retention).
SELECT experiment_id, variant, COUNT(*) n, SUM(CASE WHEN first_exposed_at IS NULL THEN 1 ELSE 0 END) never_exposed,
  SUM(CASE WHEN projects_7d>=1 AND tasks_done_7d>=3 THEN 1 ELSE 0 END) activated, SUM(CASE WHEN invites_3d>=1 THEN 1 ELSE 0 END) invited_3d,
  SUM(mature_w4) n_w4, SUM(CASE WHEN mature_w4=1 THEN w4 ELSE 0 END) w4_ret, SUM(mature_w12) n_w12, SUM(CASE WHEN mature_w12=1 THEN w12 ELSE 0 END) w12_ret,
  SUM(paid_30d) paid_30d, SUM(mature_paid) n_paid
FROM xa GROUP BY 1,2 ORDER BY 1,2;

-- name: ab02_arm_counts_by_platform
SELECT experiment_id, platform, variant, COUNT(*) n, SUM(CASE WHEN projects_7d>=1 AND tasks_done_7d>=3 THEN 1 ELSE 0 END) activated, SUM(CASE WHEN invites_3d>=1 THEN 1 ELSE 0 END) invited_3d,
  SUM(mature_w4) n_w4, SUM(CASE WHEN mature_w4=1 THEN w4 ELSE 0 END) w4_ret, SUM(paid_30d) paid_30d
FROM xa GROUP BY 1,2,3 ORDER BY 1,2,3;

-- name: ab03_arm_counts_by_size_and_channel
SELECT experiment_id, 'size' dim, size_band seg, variant, COUNT(*) n, SUM(CASE WHEN projects_7d>=1 AND tasks_done_7d>=3 THEN 1 ELSE 0 END) activated, SUM(paid_30d) paid_30d FROM xa GROUP BY 1,2,3,4
UNION ALL SELECT experiment_id, 'channel', channel, variant, COUNT(*), SUM(CASE WHEN projects_7d>=1 AND tasks_done_7d>=3 THEN 1 ELSE 0 END), SUM(paid_30d) FROM xa GROUP BY 1,2,3,4 ORDER BY 1,2,3,4;

-- name: ab04_effect_by_week_since_start
-- Novelty check: if the lift fades as the test runs, early weeks overstate the steady-state effect. Week = days from experiment start to assignment.
SELECT x.experiment_id, x.wk, x.variant, COUNT(*) n,
  SUM(CASE WHEN x.projects_7d>=1 AND x.tasks_done_7d>=3 THEN 1 ELSE 0 END) activated, SUM(x.paid_30d) paid_30d, SUM(CASE WHEN x.invites_3d>=1 THEN 1 ELSE 0 END) invited_3d
FROM xa x GROUP BY 1,2,3 ORDER BY 1,2,3;

-- name: ab05_sanity_overlap_timing_hygiene
-- (a) users in 2+ experiments (interference); (b) assignment before signup; (c) assignment lag from signup; (d) test/duplicate units inside experiments.
SELECT 'users assigned to 2+ user-level experiments' chk, COUNT(*) n FROM (SELECT unit_id FROM experiment_assignments x JOIN experiments e USING (experiment_id) WHERE e.unit_type='user' GROUP BY 1 HAVING COUNT(*)>1) z UNION ALL
SELECT 'assigned before signup (>60s)', COUNT(*) FROM xa WHERE date_diff('second', signup_at, assigned_at) < -60 UNION ALL
SELECT 'avg seconds from signup to assignment', ROUND(AVG(date_diff('second', signup_at, assigned_at)),0) FROM xa UNION ALL
SELECT 'test accounts inside experiments', COALESCE(SUM(is_test),0) FROM xa UNION ALL SELECT 'duplicate accounts inside experiments', COALESCE(SUM(is_dup),0) FROM xa UNION ALL
SELECT 'user-unit assignments that are NOT owners', COUNT(*) FROM xa JOIN users u ON u.user_id=xa.unit_id JOIN experiments e USING (experiment_id) WHERE e.unit_type='user' AND u.role<>'owner';

-- name: ab06_platform_mix_by_arm
-- Covariate balance: randomisation should give the same platform mix in both arms. An imbalance hints at a broken assignment mechanism.
SELECT experiment_id, variant, platform, COUNT(*) n FROM xa GROUP BY 1,2,3 ORDER BY 1,3,2;
