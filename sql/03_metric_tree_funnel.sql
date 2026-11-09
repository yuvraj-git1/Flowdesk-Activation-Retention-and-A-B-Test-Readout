-- ============================================================================
-- STAGE 2: ACTIVATION FUNNEL (DuckDB). Population = account OWNERS (one per signup), excluding internal test and duplicate
-- accounts. Funnel: signup -> any activity in 7d -> project created -> >=1 task done -> ACTIVATED (project + >=3 tasks done, 7d) -> week-4 retained.
-- Why owners: a "signup" is the person who creates the workspace; members are invited and have a different journey.
-- ============================================================================

-- name: f00_owner_base
DROP TABLE IF EXISTS uo;
CREATE TABLE uo AS
SELECT *, CASE WHEN projects_7d>=1 AND tasks_done_7d>=3 THEN 1 ELSE 0 END activated,
       CASE WHEN events_7d>0 THEN 1 ELSE 0 END s_active, CASE WHEN projects_7d>=1 THEN 1 ELSE 0 END s_project, CASE WHEN tasks_done_7d>=1 THEN 1 ELSE 0 END s_task
FROM uf WHERE role='owner' AND is_test=0 AND is_dup=0;
SELECT COUNT(*) clean_owners, ROUND(100.0*SUM(activated)/COUNT(*),1) activation_pct, ROUND(100.0*SUM(CASE WHEN mature_w4=1 THEN w4 ELSE 0 END)/SUM(mature_w4),1) w4_retention_pct FROM uo;

-- name: f01_trend_by_quarter
-- PM claim to test: "activation and week-4 retention are flat while signups grow".
SELECT substr(cohort,1,4) || '-Q' || CASE WHEN substr(cohort,6,2) IN ('01','02','03') THEN '1' WHEN substr(cohort,6,2) IN ('04','05','06') THEN '2' WHEN substr(cohort,6,2) IN ('07','08','09') THEN '3' ELSE '4' END q, COUNT(*) signups,
       ROUND(100.0*SUM(activated)/COUNT(*),1) activation_pct, ROUND(100.0*SUM(s_project)/COUNT(*),1) project_pct,
       ROUND(100.0*SUM(CASE WHEN mature_w4=1 THEN w4 ELSE 0 END)/NULLIF(SUM(mature_w4),0),1) w4_pct
FROM uo GROUP BY 1 ORDER BY 1;

-- name: f02_funnel_overall
-- Step-to-step conversion shows WHERE users drop; % of signups shows cumulative loss.
WITH t AS (SELECT COUNT(*) n, SUM(s_active) a, SUM(s_project) p, SUM(s_task) k, SUM(activated) act, SUM(CASE WHEN activated=1 AND mature_w4=1 AND w4=1 THEN 1 ELSE 0 END) r, SUM(CASE WHEN activated=1 AND mature_w4=1 THEN 1 ELSE 0 END) rd FROM uo)
SELECT '1 signup' step, n users, 100.0 pct_of_signups, NULL step_conv FROM t UNION ALL
SELECT '2 any activity in 7d', a, ROUND(100.0*a/n,1), ROUND(100.0*a/n,1) FROM t UNION ALL
SELECT '3 project created', p, ROUND(100.0*p/n,1), ROUND(100.0*p/a,1) FROM t UNION ALL
SELECT '4 >=1 task completed', k, ROUND(100.0*k/n,1), ROUND(100.0*k/p,1) FROM t UNION ALL
SELECT '5 ACTIVATED (project + 3 tasks)', act, ROUND(100.0*act/n,1), ROUND(100.0*act/k,1) FROM t;

-- name: f03_funnel_by_channel
SELECT channel seg, COUNT(*) signups, ROUND(100.0*SUM(s_active)/COUNT(*),1) active_pct, ROUND(100.0*SUM(s_project)/COUNT(*),1) project_pct, ROUND(100.0*SUM(s_task)/COUNT(*),1) task_pct,
       ROUND(100.0*SUM(activated)/COUNT(*),1) activated_pct, ROUND(100.0*SUM(CASE WHEN mature_w4=1 THEN w4 ELSE 0 END)/SUM(mature_w4),1) w4_pct,
       ROUND(100.0*SUM(CASE WHEN mature_w4=1 AND activated=1 THEN w4 ELSE 0 END)/NULLIF(SUM(CASE WHEN mature_w4=1 AND activated=1 THEN 1 ELSE 0 END),0),1) w4_if_activated
FROM uo GROUP BY 1 ORDER BY 6 DESC;

-- name: f04_funnel_by_device
SELECT platform seg, COUNT(*) signups, ROUND(100.0*SUM(s_active)/COUNT(*),1) active_pct, ROUND(100.0*SUM(s_project)/COUNT(*),1) project_pct, ROUND(100.0*SUM(s_task)/COUNT(*),1) task_pct,
       ROUND(100.0*SUM(activated)/COUNT(*),1) activated_pct, ROUND(100.0*SUM(CASE WHEN mature_w4=1 THEN w4 ELSE 0 END)/SUM(mature_w4),1) w4_pct
FROM uo GROUP BY 1 ORDER BY 6 DESC;

-- name: f05_funnel_by_company_size
SELECT size_band seg, COUNT(*) signups, ROUND(100.0*SUM(s_active)/COUNT(*),1) active_pct, ROUND(100.0*SUM(s_project)/COUNT(*),1) project_pct, ROUND(100.0*SUM(s_task)/COUNT(*),1) task_pct,
       ROUND(100.0*SUM(activated)/COUNT(*),1) activated_pct, ROUND(100.0*SUM(CASE WHEN mature_w4=1 THEN w4 ELSE 0 END)/SUM(mature_w4),1) w4_pct
FROM uo GROUP BY 1 ORDER BY 1;

-- name: f06_data_cleaning_effect_on_activation
-- How much does careless handling move the headline? (a) include test+dup accounts; (b) skip android double-fire dedup (all users, android, Oct-Nov 2024).
WITH a AS (SELECT 'all owners incl. test+dup' v, COUNT(*) n, ROUND(100.0*AVG(CASE WHEN projects_7d>=1 AND tasks_done_7d>=3 THEN 1.0 ELSE 0.0 END),2) act FROM uf WHERE role='owner'
           UNION ALL SELECT 'clean owners', COUNT(*), ROUND(100.0*AVG(activated),2) FROM uo),
 raw AS (SELECT u.user_id, SUM(CASE WHEN e.event_name='task_completed' AND date_diff('second', u.created_at, e.event_ts) >= 0 AND date_diff('second', u.created_at, e.event_ts) < 604800 THEN 1 ELSE 0 END) tasks_raw
         FROM users u JOIN events e ON e.user_id=u.user_id WHERE u.first_platform='android' AND u.created_at >= '2024-10-14' AND u.created_at < '2024-11-04' GROUP BY 1)
SELECT v, n, act FROM a UNION ALL
SELECT 'android signups Oct14-Nov3 2024: activation with raw events', COUNT(*), ROUND(100.0*AVG(CASE WHEN f.projects_7d>=1 AND r.tasks_raw>=3 THEN 1.0 ELSE 0.0 END),2) FROM raw r JOIN uf f USING (user_id) UNION ALL
SELECT 'android signups Oct14-Nov3 2024: activation after dedup', COUNT(*), ROUND(100.0*AVG(CASE WHEN f.projects_7d>=1 AND f.tasks_done_7d>=3 THEN 1.0 ELSE 0.0 END),2) FROM raw r JOIN uf f USING (user_id);

-- name: f07_activation_by_signup_month_android_vs_web
-- Does the double-fire show up as a visible bump in the monthly series?
SELECT cohort, platform, COUNT(*) signups, ROUND(100.0*SUM(activated)/COUNT(*),1) activated_pct FROM uo WHERE cohort BETWEEN '2024-08' AND '2024-12' GROUP BY 1,2 ORDER BY 1,2;
