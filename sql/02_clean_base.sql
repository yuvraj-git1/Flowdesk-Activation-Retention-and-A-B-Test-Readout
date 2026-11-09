-- ============================================================================
-- STAGE 1b/2 base tables (DuckDB). Everything later reads ev (clean events) and uf (one row per user).
-- Cleaning rules (each proven in 01_profiling.sql):
--   R1 iOS event_ts is device-local time -> subtract the account's UTC offset (fixed offsets, no DST: matches the data)
--   R2 task events repeated for the same (user, task_id, event_name) are double-fires -> keep the first
--   R3 time is stored as SECONDS SINCE THE USER'S SIGNUP (sec), so every window (7d, 3d, week k) is a simple range
-- ============================================================================

-- name: b01_tz_offsets
DROP TABLE IF EXISTS tzoff;
CREATE TABLE tzoff AS
SELECT 'America/New_York' timezone, -18000 off UNION ALL SELECT 'America/Chicago', -21600 UNION ALL SELECT 'America/Los_Angeles', -28800 UNION ALL SELECT 'America/Toronto', -18000
UNION ALL SELECT 'America/Sao_Paulo', -10800 UNION ALL SELECT 'Europe/London', 0 UNION ALL SELECT 'Europe/Berlin', 3600 UNION ALL SELECT 'Europe/Paris', 3600
UNION ALL SELECT 'Europe/Amsterdam', 3600 UNION ALL SELECT 'Europe/Madrid', 3600 UNION ALL SELECT 'Asia/Kolkata', 19800 UNION ALL SELECT 'Australia/Sydney', 36000;
SELECT COUNT(*) tz_rows FROM tzoff;

-- name: b02_clean_events
DROP TABLE IF EXISTS ev;
CREATE TABLE ev AS
WITH k AS (SELECT user_id, task_id, event_name, MIN(event_id) keep_id FROM events WHERE task_id IS NOT NULL GROUP BY 1,2,3 HAVING COUNT(*) > 1)
SELECT e.user_id, e.event_name, e.platform,
       date_diff('second', u.created_at, e.event_ts) - CASE WHEN e.platform='ios' THEN COALESCE(t.off, 0) ELSE 0 END AS sec
FROM events e JOIN users u ON u.user_id = e.user_id JOIN accounts a ON a.account_id = e.account_id LEFT JOIN tzoff t ON t.timezone = a.timezone
LEFT JOIN k ON k.user_id=e.user_id AND k.task_id=e.task_id AND k.event_name=e.event_name
WHERE k.keep_id IS NULL OR e.event_id = k.keep_id;
CREATE INDEX ix_ev_user ON ev(user_id);
SELECT (SELECT COUNT(*) FROM events) raw_events, COUNT(*) clean_events, SUM(CASE WHEN sec < -60 THEN 1 ELSE 0 END) still_before_signup_gt_1min FROM ev;

-- name: b03_account_dimensions
-- Channel normalisation (46 raw labels -> 9). Flags: internal test accounts and duplicate signups (same domain, <=30 days after an earlier account).
DROP TABLE IF EXISTS acct_dim;
CREATE TABLE acct_dim AS
SELECT a.account_id, a.company_size_band size_band, a.acquisition_motion motion, a.country,
  CASE WHEN lower(trim(signup_source)) IN ('organic_search','organic','organic search','seo','google organic') THEN 'organic_search'
       WHEN lower(trim(signup_source)) IN ('direct','(direct)','none','direct / none') THEN 'direct'
       WHEN lower(trim(signup_source)) IN ('referral','word of mouth','referral_friend','ref') THEN 'referral'
       WHEN lower(trim(signup_source)) IN ('paid_search','google ads','google / cpc','adwords','googleads','ppc') THEN 'paid_search'
       WHEN lower(trim(signup_source)) IN ('paid_social','fb','facebook ads','facebook','linkedin ads','social_paid') THEN 'paid_social'
       WHEN lower(trim(signup_source)) IN ('review_site','g2','g2 crowd','capterra','capterra review','getapp') THEN 'review_site'
       WHEN lower(trim(signup_source)) IN ('affiliate','partnerstack','aff') THEN 'affiliate'
       WHEN lower(trim(signup_source)) IN ('content_email','newsletter','email','blog') THEN 'content_email'
       WHEN lower(trim(signup_source)) IN ('partner','partners','integration_partner') THEN 'partner' ELSE 'UNMAPPED' END channel,
  CASE WHEN a.email_domain='flowdesk.com' THEN 1 ELSE 0 END is_test,
  CASE WHEN a.account_id IN (SELECT b.account_id FROM accounts x JOIN accounts b ON x.email_domain=b.email_domain AND x.account_id<b.account_id
        WHERE x.email_domain<>'flowdesk.com' AND b.created_at >= x.created_at AND date_diff('day', x.created_at, b.created_at) <= 30) THEN 1 ELSE 0 END is_dup
FROM accounts a;
SELECT channel, COUNT(*) accounts, SUM(is_dup) dups, SUM(is_test) tests FROM acct_dim GROUP BY 1 ORDER BY 2 DESC;

-- name: b04_user_facts
-- ONE ROW PER USER. Activation = >=1 project_created AND >=3 task_completed within 7 days of signup (sec in [0, 7d)).
-- Week k active = any non-signup event with sec in [7k days, 7k+7 days). Right-censoring: matured flags tell which cohorts can be judged.
DROP TABLE IF EXISTS uf;
CREATE TABLE uf AS
SELECT u.user_id, u.account_id, u.role, u.first_platform platform, u.created_at, substr(CAST(u.created_at AS VARCHAR),1,7) cohort,
  d.channel, d.size_band, d.motion, d.is_test, d.is_dup,
  SUM(CASE WHEN e.event_name='project_created' AND e.sec>=0 AND e.sec<604800 THEN 1 ELSE 0 END) projects_7d,
  SUM(CASE WHEN e.event_name='task_created' AND e.sec>=0 AND e.sec<604800 THEN 1 ELSE 0 END) tasks_created_7d,
  SUM(CASE WHEN e.event_name='task_completed' AND e.sec>=0 AND e.sec<604800 THEN 1 ELSE 0 END) tasks_done_7d,
  SUM(CASE WHEN e.event_name='teammate_invited' AND e.sec>=0 AND e.sec<259200 THEN 1 ELSE 0 END) invites_3d,
  SUM(CASE WHEN e.event_name='teammate_invited' AND e.sec>=0 AND e.sec<604800 THEN 1 ELSE 0 END) invites_7d,
  SUM(CASE WHEN e.event_name='session_start' AND e.sec>=0 AND e.sec<604800 THEN 1 ELSE 0 END) sessions_7d,
  SUM(CASE WHEN e.event_name='comment_added' AND e.sec>=0 AND e.sec<604800 THEN 1 ELSE 0 END) comments_7d,
  SUM(CASE WHEN e.event_name='task_assigned' AND e.sec>=0 AND e.sec<604800 THEN 1 ELSE 0 END) assigns_7d,
  SUM(CASE WHEN e.event_name='integration_connected' AND e.sec>=0 AND e.sec<604800 THEN 1 ELSE 0 END) integ_7d,
  SUM(CASE WHEN e.event_name<>'signup_completed' AND e.sec>=0 AND e.sec<604800 THEN 1 ELSE 0 END) events_7d,
  MAX(CASE WHEN e.event_name<>'signup_completed' AND e.sec>=604800*1 AND e.sec<604800*2 THEN 1 ELSE 0 END) w1,
  MAX(CASE WHEN e.event_name<>'signup_completed' AND e.sec>=604800*2 AND e.sec<604800*3 THEN 1 ELSE 0 END) w2,
  MAX(CASE WHEN e.event_name<>'signup_completed' AND e.sec>=604800*3 AND e.sec<604800*4 THEN 1 ELSE 0 END) w3,
  MAX(CASE WHEN e.event_name<>'signup_completed' AND e.sec>=604800*4 AND e.sec<604800*5 THEN 1 ELSE 0 END) w4,
  MAX(CASE WHEN e.event_name<>'signup_completed' AND e.sec>=604800*5 AND e.sec<604800*6 THEN 1 ELSE 0 END) w5,
  MAX(CASE WHEN e.event_name<>'signup_completed' AND e.sec>=604800*6 AND e.sec<604800*7 THEN 1 ELSE 0 END) w6,
  MAX(CASE WHEN e.event_name<>'signup_completed' AND e.sec>=604800*8 AND e.sec<604800*9 THEN 1 ELSE 0 END) w8,
  MAX(CASE WHEN e.event_name<>'signup_completed' AND e.sec>=604800*12 AND e.sec<604800*13 THEN 1 ELSE 0 END) w12,
  CASE WHEN u.created_at <= '2025-11-26' THEN 1 ELSE 0 END mature_w4, CASE WHEN u.created_at <= '2025-09-30' THEN 1 ELSE 0 END mature_w12
FROM users u JOIN acct_dim d ON d.account_id=u.account_id LEFT JOIN ev e ON e.user_id=u.user_id
GROUP BY u.user_id, u.account_id, u.role, u.first_platform, u.created_at, d.channel, d.size_band, d.motion, d.is_test, d.is_dup;
SELECT COUNT(*) users, SUM(CASE WHEN role='owner' THEN 1 ELSE 0 END) owners, ROUND(AVG(CASE WHEN role='owner' AND projects_7d>=1 AND tasks_done_7d>=3 THEN 1.0 END)*100,1) owner_activation_pct FROM uf;
