/* SQL Server DBA Scripts - 18. MEMORY & BUFFER POOL
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  18. MEMORY & BUFFER POOL
=====================================================================================*/
-- Process memory
SELECT  physical_memory_in_use_kb/1024 AS sql_memory_in_use_mb,
        locked_page_allocations_kb/1024 AS locked_pages_mb,
        memory_utilization_percentage, process_physical_memory_low, process_virtual_memory_low
FROM sys.dm_os_process_memory;

-- OS memory state
SELECT total_physical_memory_kb/1024 AS total_mb, available_physical_memory_kb/1024 AS available_mb,
       system_memory_state_desc
FROM sys.dm_os_sys_memory;

-- Page life expectancy & key memory counters
SELECT object_name, counter_name, cntr_value
FROM sys.dm_os_performance_counters
WHERE (object_name LIKE '%Buffer Manager%' AND counter_name IN ('Page life expectancy','Buffer cache hit ratio','Lazy writes/sec'))
   OR (object_name LIKE '%Memory Manager%' AND counter_name IN ('Memory Grants Pending','Target Server Memory (KB)','Total Server Memory (KB)'));

-- Buffer pool usage per database
SELECT  CASE database_id WHEN 32767 THEN 'ResourceDb' ELSE DB_NAME(database_id) END AS database_name,
        COUNT(*)*8/1024 AS cached_mb,
        SUM(CASE WHEN is_modified = 1 THEN 1 ELSE 0 END)*8/1024 AS dirty_mb
FROM sys.dm_os_buffer_descriptors
GROUP BY database_id
ORDER BY cached_mb DESC;

-- Top memory clerks
SELECT TOP (15) type, name, SUM(pages_kb)/1024 AS size_mb
FROM sys.dm_os_memory_clerks
GROUP BY type, name
ORDER BY size_mb DESC;

-- Pending memory grants
SELECT session_id, requested_memory_kb/1024 AS requested_mb, granted_memory_kb/1024 AS granted_mb,
       wait_time_ms, queue_id, dop, query_cost
FROM sys.dm_exec_query_memory_grants
ORDER BY requested_memory_kb DESC;
