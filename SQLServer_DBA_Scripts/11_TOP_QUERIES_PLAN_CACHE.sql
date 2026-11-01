/* SQL Server DBA Scripts - 11. TOP QUERIES & PLAN CACHE
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  11. TOP QUERIES & PLAN CACHE
=====================================================================================*/
-- Top 25 by total CPU (change ORDER BY for reads/duration/executions)
SELECT TOP (25)
        DB_NAME(t.dbid) AS database_name,
        qs.execution_count,
        qs.total_worker_time/1000                          AS total_cpu_ms,
        qs.total_worker_time/qs.execution_count/1000       AS avg_cpu_ms,
        qs.total_elapsed_time/qs.execution_count/1000      AS avg_duration_ms,
        qs.total_logical_reads/qs.execution_count          AS avg_logical_reads,
        qs.total_logical_writes/qs.execution_count         AS avg_logical_writes,
        qs.total_grant_kb/NULLIF(qs.execution_count,0)/1024 AS avg_grant_mb,
        qs.creation_time, qs.last_execution_time,
        SUBSTRING(t.text, qs.statement_start_offset/2 + 1,
            (CASE WHEN qs.statement_end_offset = -1 THEN DATALENGTH(t.text)
                  ELSE qs.statement_end_offset END - qs.statement_start_offset)/2 + 1) AS statement_text,
        qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) t
OUTER APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
ORDER BY qs.total_worker_time DESC;
-- ORDER BY qs.total_logical_reads DESC;
-- ORDER BY qs.total_elapsed_time DESC;
-- ORDER BY qs.execution_count DESC;

-- Top stored procedures
SELECT TOP (25)
        DB_NAME(ps.database_id) AS database_name,
        OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id) + '.' + OBJECT_NAME(ps.object_id, ps.database_id) AS proc_name,
        ps.execution_count, ps.total_worker_time/1000 AS total_cpu_ms,
        ps.total_elapsed_time/ps.execution_count/1000 AS avg_duration_ms,
        ps.total_logical_reads/ps.execution_count AS avg_reads,
        ps.cached_time, ps.last_execution_time
FROM sys.dm_exec_procedure_stats ps
ORDER BY ps.total_worker_time DESC;

-- Plan cache composition (single-use plan bloat)
SELECT  objtype, cacheobjtype, COUNT(*) AS plans,
        SUM(CAST(size_in_bytes AS BIGINT))/1048576 AS size_mb,
        SUM(CASE WHEN usecounts = 1 THEN 1 ELSE 0 END) AS single_use_plans,
        SUM(CASE WHEN usecounts = 1 THEN CAST(size_in_bytes AS BIGINT) ELSE 0 END)/1048576 AS single_use_mb
FROM sys.dm_exec_cached_plans
GROUP BY objtype, cacheobjtype
ORDER BY size_mb DESC;

-- Plans with implicit conversions / missing index warnings (expensive - run off-peak)
SELECT TOP (50) DB_NAME(t.dbid) AS database_name, cp.usecounts, t.text, qp.query_plan
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) t
WHERE CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%CONVERT_IMPLICIT%'
   OR CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%MissingIndexGroup%'
ORDER BY cp.usecounts DESC;

/* [CHANGES DATA] Remove one plan / clear cache for a database
DBCC FREEPROCCACHE (0x060006001ECA270EC0215D05000000000000000000000000); -- plan_handle
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;               -- current DB only
*/
