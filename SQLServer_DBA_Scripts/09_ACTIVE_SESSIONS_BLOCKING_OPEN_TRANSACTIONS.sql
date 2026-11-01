/* SQL Server DBA Scripts - 09. ACTIVE SESSIONS, BLOCKING, OPEN TRANSACTIONS
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  09. ACTIVE SESSIONS, BLOCKING, OPEN TRANSACTIONS
=====================================================================================*/
-- Currently executing requests
SELECT  r.session_id, r.blocking_session_id AS blocked_by, s.login_name, s.host_name,
        s.program_name, DB_NAME(r.database_id) AS database_name, r.status, r.command,
        r.wait_type, r.wait_time, r.wait_resource, r.cpu_time,
        r.total_elapsed_time/1000 AS elapsed_s, r.logical_reads, r.writes,
        r.granted_query_memory*8/1024 AS grant_mb, r.dop,
        SUBSTRING(t.text, r.statement_start_offset/2 + 1,
            (CASE WHEN r.statement_end_offset = -1 THEN DATALENGTH(t.text)
                  ELSE r.statement_end_offset END - r.statement_start_offset)/2 + 1) AS current_statement,
        t.text AS batch_text, p.query_plan
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) p
WHERE r.session_id <> @@SPID AND s.is_user_process = 1
ORDER BY r.total_elapsed_time DESC;

-- Blocking chain (head blockers first)
WITH b AS (
    SELECT s.session_id, ISNULL(r.blocking_session_id,0) AS blocking_session_id,
           s.login_name, s.host_name, s.program_name, r.wait_type, r.wait_time,
           r.wait_resource, DB_NAME(COALESCE(r.database_id, s.database_id)) AS database_name,
           COALESCE(t.text, ib.event_info) AS sql_text
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
    OUTER APPLY sys.dm_exec_input_buffer(s.session_id, NULL) ib
    WHERE s.session_id IN (SELECT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id > 0)
       OR r.blocking_session_id > 0
),
chain AS (
    SELECT session_id, blocking_session_id, 0 AS lvl,
           CAST(RIGHT('00000'+CAST(session_id AS VARCHAR(10)),5) AS VARCHAR(1000)) AS path
    FROM b WHERE blocking_session_id = 0
    UNION ALL
    SELECT b.session_id, b.blocking_session_id, c.lvl + 1,
           CAST(c.path + '>' + RIGHT('00000'+CAST(b.session_id AS VARCHAR(10)),5) AS VARCHAR(1000))
    FROM b JOIN chain c ON b.blocking_session_id = c.session_id
)
SELECT REPLICATE('    ', c.lvl) + CAST(c.session_id AS VARCHAR(10)) AS blocking_tree,
       b.login_name, b.host_name, b.program_name, b.database_name,
       b.wait_type, b.wait_time, b.wait_resource, b.sql_text
FROM chain c JOIN b ON b.session_id = c.session_id
ORDER BY c.path;

-- Open transactions (long-running / idle-in-transaction)
SELECT  st.session_id, s.login_name, s.host_name, s.program_name, s.status,
        at.transaction_begin_time,
        DATEDIFF(SECOND, at.transaction_begin_time, GETDATE()) AS open_seconds,
        DB_NAME(dt.database_id) AS database_name,
        dt.database_transaction_log_bytes_used/1048576.0 AS log_used_mb,
        ib.event_info AS last_sql
FROM sys.dm_tran_session_transactions st
JOIN sys.dm_tran_active_transactions at   ON at.transaction_id = st.transaction_id
JOIN sys.dm_tran_database_transactions dt ON dt.transaction_id = st.transaction_id
JOIN sys.dm_exec_sessions s               ON s.session_id = st.session_id
OUTER APPLY sys.dm_exec_input_buffer(st.session_id, NULL) ib
ORDER BY at.transaction_begin_time;

-- Oldest active transaction in current DB
DBCC OPENTRAN;

-- Connections summary
SELECT  DB_NAME(s.database_id) AS database_name, s.login_name, s.host_name, s.program_name,
        COUNT(*) AS sessions, SUM(CASE WHEN s.status = 'running' THEN 1 ELSE 0 END) AS running
FROM sys.dm_exec_sessions s
WHERE s.is_user_process = 1
GROUP BY DB_NAME(s.database_id), s.login_name, s.host_name, s.program_name
ORDER BY sessions DESC;

-- Lock summary
SELECT  DB_NAME(resource_database_id) AS database_name, resource_type, request_mode,
        request_status, COUNT(*) AS lock_count
FROM sys.dm_tran_locks
GROUP BY resource_database_id, resource_type, request_mode, request_status
ORDER BY lock_count DESC;
