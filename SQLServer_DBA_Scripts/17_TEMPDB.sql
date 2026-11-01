/* SQL Server DBA Scripts - 17. TEMPDB
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  17. TEMPDB
=====================================================================================*/
-- TempDB files (should be equal size, equal growth)
SELECT name, physical_name, size*8/1024 AS size_mb,
       CASE WHEN is_percent_growth = 1 THEN CAST(growth AS VARCHAR) + '%' ELSE CAST(growth*8/1024 AS VARCHAR) + ' MB' END AS growth
FROM tempdb.sys.database_files;

-- TempDB space by consumer
SELECT  SUM(user_object_reserved_page_count)*8/1024     AS user_objects_mb,
        SUM(internal_object_reserved_page_count)*8/1024 AS internal_objects_mb,
        SUM(version_store_reserved_page_count)*8/1024   AS version_store_mb,
        SUM(unallocated_extent_page_count)*8/1024       AS free_mb,
        SUM(mixed_extent_page_count)*8/1024             AS mixed_extents_mb
FROM tempdb.sys.dm_db_file_space_usage;

-- Sessions using the most tempdb
SELECT TOP (20) su.session_id, s.login_name, s.host_name, s.program_name,
       (su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count
        + ISNULL(tu.user_alloc,0) + ISNULL(tu.internal_alloc,0))*8/1024 AS tempdb_alloc_mb,
       ib.event_info AS last_sql
FROM sys.dm_db_session_space_usage su
JOIN sys.dm_exec_sessions s ON s.session_id = su.session_id
OUTER APPLY (SELECT SUM(user_objects_alloc_page_count) AS user_alloc,
                    SUM(internal_objects_alloc_page_count) AS internal_alloc
             FROM sys.dm_db_task_space_usage WHERE session_id = su.session_id) tu
OUTER APPLY sys.dm_exec_input_buffer(su.session_id, NULL) ib
WHERE su.session_id > 50
ORDER BY tempdb_alloc_mb DESC;

-- TempDB allocation contention (PAGELATCH on 2:x:1/2/3)
SELECT session_id, wait_type, wait_duration_ms, resource_description
FROM sys.dm_os_waiting_tasks
WHERE wait_type LIKE 'PAGELATCH%' AND resource_description LIKE '2:%';

/* [CHANGES CONFIG] Add / resize tempdb files (takes effect immediately for new files)
ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev, SIZE = 8192MB, FILEGROWTH = 1024MB);
ALTER DATABASE tempdb ADD FILE (NAME = tempdev2, FILENAME = 'T:\TempDB\tempdev2.ndf', SIZE = 8192MB, FILEGROWTH = 1024MB);
*/
