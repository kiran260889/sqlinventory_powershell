/* SQL Server DBA Scripts - 12. QUERY STORE (run in the target database)
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  12. QUERY STORE (run in the target database)
=====================================================================================*/
-- Query Store state
SELECT actual_state_desc, desired_state_desc, readonly_reason,
       current_storage_size_mb, max_storage_size_mb, query_capture_mode_desc,
       size_based_cleanup_mode_desc, stale_query_threshold_days
FROM sys.database_query_store_options;

-- Top queries by CPU, last 24h
SELECT TOP (25)
        q.query_id, p.plan_id, OBJECT_NAME(q.object_id) AS object_name,
        SUM(rs.count_executions) AS executions,
        SUM(rs.avg_cpu_time * rs.count_executions)/1000 AS total_cpu_ms,
        AVG(rs.avg_duration)/1000 AS avg_duration_ms,
        AVG(rs.avg_logical_io_reads) AS avg_reads,
        qt.query_sql_text
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt         ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan p                ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats rs      ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval i ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE i.start_time >= DATEADD(HOUR,-24,SYSUTCDATETIME())
GROUP BY q.query_id, p.plan_id, q.object_id, qt.query_sql_text
ORDER BY total_cpu_ms DESC;

-- Queries with multiple plans (plan regression candidates)
SELECT q.query_id, COUNT(DISTINCT p.plan_id) AS plan_count, qt.query_sql_text
FROM sys.query_store_query q
JOIN sys.query_store_plan p        ON p.query_id = q.query_id
JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
GROUP BY q.query_id, qt.query_sql_text
HAVING COUNT(DISTINCT p.plan_id) > 1
ORDER BY plan_count DESC;

-- Forced plans
SELECT p.query_id, p.plan_id, p.is_forced_plan, p.force_failure_count, p.last_force_failure_reason_desc
FROM sys.query_store_plan p WHERE p.is_forced_plan = 1;

/* [CHANGES CONFIG]
ALTER DATABASE [YourDB] SET QUERY_STORE = ON
  (OPERATION_MODE = READ_WRITE, MAX_STORAGE_SIZE_MB = 2048, QUERY_CAPTURE_MODE = AUTO,
   CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30), SIZE_BASED_CLEANUP_MODE = AUTO);
EXEC sys.sp_query_store_force_plan   @query_id = 123, @plan_id = 456;
EXEC sys.sp_query_store_unforce_plan @query_id = 123, @plan_id = 456;
*/
