/* SQL Server DBA Scripts - 06. BACKUPS: HISTORY, MISSING, CHAIN
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  06. BACKUPS: HISTORY, MISSING, CHAIN
=====================================================================================*/
-- Last backup of each type per database
SELECT  d.name AS database_name, d.recovery_model_desc,
        MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS last_full,
        MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS last_diff,
        MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS last_log
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b ON b.database_name = d.name AND b.is_copy_only = 0
WHERE d.name <> 'tempdb'
GROUP BY d.name, d.recovery_model_desc
ORDER BY d.name;

-- Databases with no FULL backup in 24h, or no LOG backup in 1h (FULL recovery)
SELECT d.name, d.recovery_model_desc, x.last_full, x.last_log,
       CASE WHEN x.last_full IS NULL OR x.last_full < DATEADD(HOUR,-24,GETDATE()) THEN 'FULL OVERDUE' ELSE '' END AS full_alert,
       CASE WHEN d.recovery_model_desc <> 'SIMPLE'
             AND (x.last_log IS NULL OR x.last_log < DATEADD(HOUR,-1,GETDATE())) THEN 'LOG OVERDUE' ELSE '' END AS log_alert
FROM sys.databases d
OUTER APPLY (SELECT MAX(CASE WHEN type IN ('D','I') THEN backup_finish_date END) AS last_full,
                    MAX(CASE WHEN type = 'L' THEN backup_finish_date END)        AS last_log
             FROM msdb.dbo.backupset WHERE database_name = d.name) x
WHERE d.name <> 'tempdb' AND d.state_desc = 'ONLINE'
  AND (x.last_full IS NULL OR x.last_full < DATEADD(HOUR,-24,GETDATE())
       OR (d.recovery_model_desc <> 'SIMPLE' AND (x.last_log IS NULL OR x.last_log < DATEADD(HOUR,-1,GETDATE()))));

-- Backup history, last 7 days, with size, speed and file
SELECT  b.database_name,
        CASE b.type WHEN 'D' THEN 'Full' WHEN 'I' THEN 'Diff' WHEN 'L' THEN 'Log' ELSE b.type END AS backup_type,
        b.backup_start_date, b.backup_finish_date,
        DATEDIFF(SECOND, b.backup_start_date, b.backup_finish_date) AS duration_s,
        CAST(b.backup_size/1048576.0 AS DECIMAL(18,2))            AS size_mb,
        CAST(b.compressed_backup_size/1048576.0 AS DECIMAL(18,2)) AS compressed_mb,
        b.is_copy_only, b.has_backup_checksums, b.first_lsn, b.last_lsn,
        mf.physical_device_name, b.user_name
FROM msdb.dbo.backupset b
JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = b.media_set_id
WHERE b.backup_start_date >= DATEADD(DAY,-7,GETDATE())
ORDER BY b.backup_start_date DESC;

-- Restore history
SELECT  rh.destination_database_name, rh.restore_date, rh.user_name,
        CASE rh.restore_type WHEN 'D' THEN 'Full' WHEN 'I' THEN 'Diff' WHEN 'L' THEN 'Log' ELSE rh.restore_type END AS restore_type,
        bs.backup_finish_date AS backup_taken, mf.physical_device_name
FROM msdb.dbo.restorehistory rh
JOIN msdb.dbo.backupset bs         ON bs.backup_set_id = rh.backup_set_id
JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id  = bs.media_set_id
ORDER BY rh.restore_date DESC;

-- Progress of running backup/restore/DBCC
SELECT  r.session_id, r.command, r.percent_complete,
        r.start_time, DATEADD(SECOND, r.estimated_completion_time/1000, GETDATE()) AS est_finish,
        r.wait_type, DB_NAME(r.database_id) AS database_name, t.text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.command LIKE 'BACKUP%' OR r.command LIKE 'RESTORE%' OR r.command LIKE 'DBCC%';
