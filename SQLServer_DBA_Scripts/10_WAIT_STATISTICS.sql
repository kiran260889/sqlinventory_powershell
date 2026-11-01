/* SQL Server DBA Scripts - 10. WAIT STATISTICS
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  10. WAIT STATISTICS
=====================================================================================*/
WITH waits AS (
    SELECT wait_type, wait_time_ms/1000.0 AS wait_s,
           (wait_time_ms - signal_wait_time_ms)/1000.0 AS resource_s,
           signal_wait_time_ms/1000.0 AS signal_s, waiting_tasks_count,
           100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS pct,
           ROW_NUMBER() OVER (ORDER BY wait_time_ms DESC) AS rn
    FROM sys.dm_os_wait_stats
    WHERE waiting_tasks_count > 0 AND wait_type NOT IN (
        'BROKER_EVENTHANDLER','BROKER_RECEIVE_WAITFOR','BROKER_TASK_STOP','BROKER_TO_FLUSH',
        'BROKER_TRANSMITTER','CHECKPOINT_QUEUE','CHKPT','CLR_AUTO_EVENT','CLR_MANUAL_EVENT',
        'CLR_SEMAPHORE','DBMIRROR_DBM_EVENT','DBMIRROR_EVENTS_QUEUE','DBMIRROR_WORKER_QUEUE',
        'DBMIRRORING_CMD','DIRTY_PAGE_POLL','DISPATCHER_QUEUE_SEMAPHORE','EXECSYNC','FSAGENT',
        'FT_IFTS_SCHEDULER_IDLE_WAIT','FT_IFTSHC_MUTEX','HADR_CLUSAPI_CALL',
        'HADR_FILESTREAM_IOMGR_IOCOMPLETION','HADR_LOGCAPTURE_WAIT','HADR_NOTIFICATION_DEQUEUE',
        'HADR_TIMER_TASK','HADR_WORK_QUEUE','KSOURCE_WAKEUP','LAZYWRITER_SLEEP','LOGMGR_QUEUE',
        'MEMORY_ALLOCATION_EXT','ONDEMAND_TASK_QUEUE','PARALLEL_REDO_DRAIN_WORKER',
        'PARALLEL_REDO_LOG_CACHE','PARALLEL_REDO_TRAN_LIST','PARALLEL_REDO_WORKER_SYNC',
        'PARALLEL_REDO_WORKER_WAIT_WORK','PREEMPTIVE_XE_GETTARGETSTATE',
        'PWAIT_ALL_COMPONENTS_INITIALIZED','PWAIT_DIRECTLOGCONSUMER_GETNEXT',
        'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP','QDS_ASYNC_QUEUE',
        'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP','QDS_SHUTDOWN_QUEUE',
        'REDO_THREAD_PENDING_WORK','REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE',
        'SERVER_IDLE_CHECK','SLEEP_BPOOL_FLUSH','SLEEP_DBSTARTUP','SLEEP_DCOMSTARTUP',
        'SLEEP_MASTERDBREADY','SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP',
        'SLEEP_SYSTEMTASK','SLEEP_TASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
        'SOS_WORK_DISPATCHER','SP_SERVER_DIAGNOSTICS_SLEEP','SQLTRACE_BUFFER_FLUSH',
        'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','SQLTRACE_WAIT_ENTRIES','VDI_CLIENT_OTHER',
        'WAIT_FOR_RESULTS','WAITFOR','WAITFOR_TASKSHUTDOWN','WAIT_XTP_RECOVERY',
        'WAIT_XTP_HOST_WAIT','WAIT_XTP_OFFLINE_CKPT_NEW_LOG','WAIT_XTP_CKPT_CLOSE',
        'XE_DISPATCHER_JOIN','XE_DISPATCHER_WAIT','XE_TIMER_EVENT')
      AND wait_type NOT LIKE 'PREEMPTIVE_OS_%' AND wait_type NOT LIKE 'SLEEP_%'
)
SELECT TOP (25) wait_type,
       CAST(wait_s AS DECIMAL(18,1))     AS wait_s,
       CAST(resource_s AS DECIMAL(18,1)) AS resource_s,
       CAST(signal_s AS DECIMAL(18,1))   AS signal_s,
       waiting_tasks_count,
       CAST(wait_s*1000/waiting_tasks_count AS DECIMAL(18,2)) AS avg_wait_ms,
       CAST(pct AS DECIMAL(5,2)) AS pct,
       CAST(SUM(pct) OVER (ORDER BY rn) AS DECIMAL(5,2)) AS running_pct
FROM waits ORDER BY rn;

-- Current waiting tasks
SELECT  wt.session_id, wt.wait_type, wt.wait_duration_ms, wt.blocking_session_id,
        wt.resource_description, DB_NAME(r.database_id) AS database_name, t.text
FROM sys.dm_os_waiting_tasks wt
LEFT JOIN sys.dm_exec_requests r ON r.session_id = wt.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE wt.session_id > 50
ORDER BY wt.wait_duration_ms DESC;

-- Signal vs resource wait ratio (high signal % = CPU pressure)
SELECT CAST(100.0*SUM(signal_wait_time_ms)/SUM(wait_time_ms) AS DECIMAL(5,2)) AS signal_wait_pct
FROM sys.dm_os_wait_stats;

/* [CHANGES DATA] Reset wait stats (clears baseline)
DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);
*/
