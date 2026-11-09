-- ============================================================================
-- STAGE 1: PROFILE + VALIDATE (DuckDB). Goal: know each table's grain, keys and which columns can't be trusted
-- BEFORE computing a single product metric. Each block = one test.
-- ============================================================================

-- name: p01_counts_and_ranges
SELECT 'accounts' t, COUNT(*) n, MIN(created_at) first_ts, MAX(created_at) last_ts FROM accounts UNION ALL
SELECT 'users', COUNT(*), MIN(created_at), MAX(created_at) FROM users UNION ALL
SELECT 'events', COUNT(*), MIN(event_ts), MAX(event_ts) FROM events UNION ALL
SELECT 'experiments', COUNT(*), MIN(start_date), MAX(end_date) FROM experiments UNION ALL
SELECT 'experiment_assignments', COUNT(*), MIN(assigned_at), MAX(assigned_at) FROM experiment_assignments;

-- name: p02_keys_and_orphans
-- Keys must be unique; FKs must resolve. Orphan events would silently vanish from any INNER JOIN funnel.
SELECT 'events.event_id dup' chk, COUNT(*) - COUNT(DISTINCT event_id) n FROM events UNION ALL
SELECT 'users.user_id dup', COUNT(*) - COUNT(DISTINCT user_id) FROM users UNION ALL
SELECT 'accounts.account_id dup', COUNT(*) - COUNT(DISTINCT account_id) FROM accounts UNION ALL
SELECT 'events -> users orphans', COUNT(*) FROM events e LEFT JOIN users u USING (user_id) WHERE u.user_id IS NULL UNION ALL
SELECT 'events.account_id <> users.account_id', COUNT(*) FROM events e JOIN users u USING (user_id) WHERE e.account_id <> u.account_id UNION ALL
SELECT 'users -> accounts orphans', COUNT(*) FROM users u LEFT JOIN accounts a USING (account_id) WHERE a.account_id IS NULL UNION ALL
SELECT 'assignments -> experiments orphans', COUNT(*) FROM experiment_assignments x LEFT JOIN experiments e USING (experiment_id) WHERE e.experiment_id IS NULL UNION ALL
SELECT 'accounts with !=1 owner', COUNT(*) FROM (SELECT a.account_id FROM accounts a LEFT JOIN users u ON u.account_id=a.account_id AND u.role='owner' GROUP BY 1 HAVING COUNT(u.user_id) <> 1) z;

-- name: p03_event_and_platform_mix
SELECT event_name, COUNT(*) n, ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM events),1) pct, COUNT(DISTINCT user_id) users FROM events GROUP BY 1 ORDER BY 2 DESC;

-- name: p04_platform_version_mix
SELECT platform, app_version, COUNT(*) n, MIN(event_ts) first_seen, MAX(event_ts) last_seen FROM events GROUP BY 1,2 ORDER BY 1, 4;

-- name: p05_timestamp_sanity_by_platform_tz
-- If event_ts is UTC, event_ts <= ingested_at (the warehouse can't receive an event before it happens).
-- avg(event_ts - ingested_at) in minutes: ~0 or negative = UTC. A value near the account's UTC offset = device-local time.
SELECT e.platform, a.timezone, COUNT(*) n, ROUND(AVG(date_diff('minute', e.ingested_at, e.event_ts))/60.0, 2) avg_event_minus_ingest_hours,
       ROUND(100.0*SUM(CASE WHEN e.event_ts > e.ingested_at THEN 1 ELSE 0 END)/COUNT(*), 1) pct_event_after_ingest
FROM events e JOIN accounts a ON a.account_id = e.account_id GROUP BY 1,2 ORDER BY 1,2;

-- name: p06_duplicate_task_events
-- A task can only be completed once per user. Same (user, task_id, event_name) repeated = double-firing. Where/when?
WITH d AS (SELECT user_id, task_id, event_name, MIN(platform) platform, MIN(app_version) app_version, MIN(event_ts) ts, COUNT(*) n
           FROM events WHERE task_id IS NOT NULL GROUP BY 1,2,3 HAVING COUNT(*) > 1)
SELECT event_name, platform, app_version, COUNT(*) dup_groups, SUM(n-1) extra_rows, MIN(ts) first_ts, MAX(ts) last_ts FROM d GROUP BY 1,2,3 ORDER BY 5 DESC;

-- name: p07_events_before_signup
SELECT COUNT(*) events_before_user_created, COUNT(DISTINCT e.user_id) users FROM events e JOIN users u USING (user_id) WHERE e.event_ts < u.created_at;

-- name: p08_account_hygiene
-- Funnel denominators must exclude internal/test and duplicate signups. Strong dup signal = same non-null domain within 30 days.
WITH d AS (SELECT DISTINCT b.account_id FROM accounts a JOIN accounts b ON a.email_domain=b.email_domain AND a.account_id<b.account_id
           WHERE a.email_domain<>'flowdesk.com' AND b.created_at >= a.created_at AND date_diff('day', a.created_at, b.created_at) <= 30)
SELECT (SELECT COUNT(*) FROM accounts) accounts, (SELECT COUNT(*) FROM accounts WHERE email_domain='flowdesk.com') internal_test,
       (SELECT COUNT(*) FROM d) duplicate_by_domain, (SELECT COUNT(DISTINCT signup_source) FROM accounts) distinct_channel_labels,
       (SELECT COUNT(*) FROM accounts WHERE industry IS NULL) null_industry, (SELECT COUNT(*) FROM users WHERE role<>'owner') non_owner_users;

-- name: p09_experiment_assignment_profile
-- Per experiment: units, variant split, exposure rate, repeated units, assignments outside the planned window.
SELECT x.experiment_id, e.name, e.unit_type, COUNT(*) assignments, COUNT(DISTINCT x.unit_id) units,
       ROUND(100.0*SUM(CASE WHEN x.variant='treatment' THEN 1 ELSE 0 END)/COUNT(*),2) pct_treatment,
       ROUND(100.0*SUM(CASE WHEN x.first_exposed_at IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) pct_never_exposed,
       SUM(CASE WHEN substr(CAST(x.assigned_at AS VARCHAR),1,10) < CAST(e.start_date AS VARCHAR) OR substr(CAST(x.assigned_at AS VARCHAR),1,10) > CAST(e.end_date AS VARCHAR) THEN 1 ELSE 0 END) outside_window
FROM experiment_assignments x JOIN experiments e USING (experiment_id) GROUP BY 1,2,3 ORDER BY 1;

-- name: p10_users_per_account_and_events_per_user
SELECT 'users per account' metric, ROUND(AVG(c),2) avg_, MAX(c) max_ FROM (SELECT account_id, COUNT(*) c FROM users GROUP BY 1) z UNION ALL
SELECT 'events per user', ROUND(AVG(c),1), MAX(c) FROM (SELECT user_id, COUNT(*) c FROM events GROUP BY 1) z;
