-- SQL commands to clear all statistics data from bridge_stats.db
-- This preserves table structure and configuration but clears all stats/usage data

-- Clear service usage statistics
DELETE FROM service_usage;

-- Clear daily unique users
DELETE FROM daily_uniques;

-- Clear geographic statistics  
DELETE FROM geo_stats;

-- Clear device statistics
DELETE FROM device_stats;

-- Clear anonymous session tracking
DELETE FROM anonymous_sessions;

-- Clear API key audit logs (but keep the API keys themselves)
DELETE FROM api_key_audit;

-- Clear security audit logs
DELETE FROM security_audit;

-- Clear rate limit logs if they exist
DELETE FROM rate_limit_logs WHERE 1=1;

-- Reset SQLite's internal sequence counters
DELETE FROM sqlite_sequence WHERE name IN (
  'service_usage', 
  'daily_uniques', 
  'geo_stats', 
  'device_stats', 
  'anonymous_sessions',
  'api_key_audit',
  'security_audit',
  'rate_limit_logs'
);

-- Vacuum to reclaim space
VACUUM;

-- Show remaining data (configuration that should be preserved)
SELECT 'Preserved Tables:' as Info;
SELECT 'API Keys: ' || COUNT(*) as Count FROM api_keys;
SELECT 'Service States: ' || COUNT(*) as Count FROM service_states;
SELECT 'Blocked IPs: ' || COUNT(*) as Count FROM blocked_ips;
SELECT 'Whitelisted IPs: ' || COUNT(*) as Count FROM whitelisted_ips;

-- Verify stats are cleared
SELECT 'Cleared Tables:' as Info;
SELECT 'Service Usage: ' || COUNT(*) as Count FROM service_usage;
SELECT 'Daily Uniques: ' || COUNT(*) as Count FROM daily_uniques;
SELECT 'Geo Stats: ' || COUNT(*) as Count FROM geo_stats;
SELECT 'Device Stats: ' || COUNT(*) as Count FROM device_stats;
SELECT 'Anonymous Sessions: ' || COUNT(*) as Count FROM anonymous_sessions;
SELECT 'API Key Audit: ' || COUNT(*) as Count FROM api_key_audit;
SELECT 'Security Audit: ' || COUNT(*) as Count FROM security_audit;