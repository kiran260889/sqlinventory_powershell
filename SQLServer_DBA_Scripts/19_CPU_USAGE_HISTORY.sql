/* SQL Server DBA Scripts - 19. CPU USAGE HISTORY (last ~4 hours, 1-minute samples)
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  19. CPU USAGE HISTORY (last ~4 hours, 1-minute samples)
=====================================================================================*/
DECLARE @ts_now BIGINT = (SELECT cpu_ticks/(cpu_ticks/ms_ticks) FROM sys.dm_os_sys_info);
SELECT TOP (240)
       DATEADD(MS, -1 * (@ts_now - [timestamp]), GETDATE()) AS sample_time,
       rec.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','int') AS sql_cpu_pct,
       rec.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]','int') AS idle_pct,
       100 - rec.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]','int')
           - rec.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','int') AS other_cpu_pct
FROM (SELECT [timestamp], CONVERT(XML, record) AS rec
      FROM sys.dm_os_ring_buffers
      WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR' AND record LIKE N'%<SystemHealth>%') x
ORDER BY sample_time DESC;

-- CPU by database (from plan cache)
WITH db_cpu AS (
    SELECT pa.DatabaseID, SUM(qs.total_worker_time)/1000 AS cpu_ms
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY (SELECT CONVERT(INT, value) AS DatabaseID FROM sys.dm_exec_plan_attributes(qs.plan_handle)
                 WHERE attribute = N'dbid') pa
    GROUP BY pa.DatabaseID
)
SELECT DB_NAME(DatabaseID) AS database_name, cpu_ms,
       CAST(100.0*cpu_ms/SUM(cpu_ms) OVER() AS DECIMAL(5,2)) AS cpu_pct
FROM db_cpu WHERE DatabaseID <> 32767
ORDER BY cpu_ms DESC;

-- Scheduler pressure (runnable tasks > 0 consistently = CPU pressure)
SELECT scheduler_id, current_tasks_count, runnable_tasks_count, active_workers_count, work_queue_count
FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE';
