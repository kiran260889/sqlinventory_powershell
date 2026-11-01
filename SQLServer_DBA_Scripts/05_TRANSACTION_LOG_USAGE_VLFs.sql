/* SQL Server DBA Scripts - 05. TRANSACTION LOG USAGE & VLFs
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  05. TRANSACTION LOG USAGE & VLFs
=====================================================================================*/
-- Log usage, all databases
DBCC SQLPERF(LOGSPACE);

-- Why can't the log truncate?
SELECT name, recovery_model_desc, log_reuse_wait_desc
FROM sys.databases
WHERE log_reuse_wait_desc <> 'NOTHING';

-- Log usage for current DB (2012+)
SELECT  DB_NAME() AS database_name,
        CAST(total_log_size_in_bytes/1048576.0 AS DECIMAL(18,2)) AS log_size_mb,
        CAST(used_log_space_in_bytes/1048576.0 AS DECIMAL(18,2)) AS used_mb,
        CAST(used_log_space_in_percent AS DECIMAL(5,2))          AS used_pct
FROM sys.dm_db_log_space_usage;

-- VLF counts, all databases (2016 SP2+). >1000 VLFs = review
SELECT  d.name, COUNT(li.database_id) AS vlf_count,
        SUM(CASE WHEN li.vlf_active = 1 THEN 1 ELSE 0 END) AS active_vlfs
FROM sys.databases d
CROSS APPLY sys.dm_db_log_info(d.database_id) li
GROUP BY d.name
ORDER BY vlf_count DESC;

/* [CHANGES DATA] Shrink log after fixing root cause (template)
USE [YourDB];
CHECKPOINT;                         -- SIMPLE recovery
-- BACKUP LOG [YourDB] TO DISK = N'...';   -- FULL recovery
DBCC SHRINKFILE (N'YourDB_log', 1024);    -- target MB
*/
