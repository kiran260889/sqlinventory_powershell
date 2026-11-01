/* SQL Server DBA Scripts - 07. BACKUP & RESTORE COMMANDS (TEMPLATES)
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  07. BACKUP & RESTORE COMMANDS (TEMPLATES)
=====================================================================================*/
/*
-- Full backup
BACKUP DATABASE [YourDB] TO DISK = N'D:\Backup\YourDB_FULL_20261101.bak'
WITH COMPRESSION, CHECKSUM, STATS = 10;

-- Differential
BACKUP DATABASE [YourDB] TO DISK = N'D:\Backup\YourDB_DIFF_20261101.bak'
WITH DIFFERENTIAL, COMPRESSION, CHECKSUM, STATS = 10;

-- Log
BACKUP LOG [YourDB] TO DISK = N'D:\Backup\YourDB_LOG_202611011500.trn'
WITH COMPRESSION, CHECKSUM;

-- Copy-only (doesn't break the diff base)
BACKUP DATABASE [YourDB] TO DISK = N'D:\Backup\YourDB_COPYONLY.bak'
WITH COPY_ONLY, COMPRESSION, CHECKSUM, STATS = 10;

-- Striped backup (faster for large DBs)
BACKUP DATABASE [YourDB]
TO DISK = N'D:\Backup\YourDB_1.bak', DISK = N'D:\Backup\YourDB_2.bak',
   DISK = N'D:\Backup\YourDB_3.bak', DISK = N'D:\Backup\YourDB_4.bak'
WITH COMPRESSION, CHECKSUM, MAXTRANSFERSIZE = 4194304, BUFFERCOUNT = 50, STATS = 5;

-- Backup to URL (Azure Blob)
-- CREATE CREDENTIAL [https://acct.blob.core.windows.net/backups]
--   WITH IDENTITY = 'SHARED ACCESS SIGNATURE', SECRET = '<sas token without ?>';
BACKUP DATABASE [YourDB] TO URL = N'https://acct.blob.core.windows.net/backups/YourDB.bak'
WITH COMPRESSION, CHECKSUM, STATS = 10;

-- Verify a backup file
RESTORE VERIFYONLY FROM DISK = N'D:\Backup\YourDB_FULL.bak' WITH CHECKSUM;
RESTORE HEADERONLY   FROM DISK = N'D:\Backup\YourDB_FULL.bak';
RESTORE FILELISTONLY FROM DISK = N'D:\Backup\YourDB_FULL.bak';

-- [CHANGES DATA] Restore with move + point-in-time
RESTORE DATABASE [YourDB_Copy] FROM DISK = N'D:\Backup\YourDB_FULL.bak'
WITH MOVE N'YourDB'     TO N'E:\Data\YourDB_Copy.mdf',
     MOVE N'YourDB_log' TO N'F:\Log\YourDB_Copy_log.ldf',
     NORECOVERY, REPLACE, STATS = 10;
RESTORE DATABASE [YourDB_Copy] FROM DISK = N'D:\Backup\YourDB_DIFF.bak' WITH NORECOVERY, STATS = 10;
RESTORE LOG      [YourDB_Copy] FROM DISK = N'D:\Backup\YourDB_LOG_1.trn' WITH NORECOVERY;
RESTORE LOG      [YourDB_Copy] FROM DISK = N'D:\Backup\YourDB_LOG_2.trn'
WITH STOPAT = '2026-11-01 14:30:00', RECOVERY;

-- Tail-log backup before restoring over a damaged DB
BACKUP LOG [YourDB] TO DISK = N'D:\Backup\YourDB_TAIL.trn' WITH NO_TRUNCATE, NORECOVERY;
*/

-- Generate restore chain (latest full -> latest diff -> logs) for one database
DECLARE @db SYSNAME = N'YourDB';
DECLARE @full_id INT, @full_lsn NUMERIC(25,0), @diff_lsn NUMERIC(25,0);

SELECT TOP 1 @full_id = backup_set_id, @full_lsn = checkpoint_lsn
FROM msdb.dbo.backupset WHERE database_name = @db AND type = 'D' AND is_copy_only = 0
ORDER BY backup_finish_date DESC;

SELECT TOP 1 @diff_lsn = last_lsn
FROM msdb.dbo.backupset WHERE database_name = @db AND type = 'I' AND differential_base_lsn = @full_lsn
ORDER BY backup_finish_date DESC;

SELECT step, cmd FROM (
    SELECT 1 AS step, b.backup_finish_date AS dt,
           'RESTORE DATABASE ' + QUOTENAME(@db) + ' FROM DISK = N''' + mf.physical_device_name + ''' WITH NORECOVERY, REPLACE, STATS = 10;' AS cmd
    FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = b.media_set_id
    WHERE b.backup_set_id = @full_id
    UNION ALL
    SELECT TOP 1 2, b.backup_finish_date,
           'RESTORE DATABASE ' + QUOTENAME(@db) + ' FROM DISK = N''' + mf.physical_device_name + ''' WITH NORECOVERY, STATS = 10;'
    FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = b.media_set_id
    WHERE b.database_name = @db AND b.type = 'I' AND b.differential_base_lsn = @full_lsn
    ORDER BY b.backup_finish_date DESC
    UNION ALL
    SELECT 3, b.backup_finish_date,
           'RESTORE LOG ' + QUOTENAME(@db) + ' FROM DISK = N''' + mf.physical_device_name + ''' WITH NORECOVERY;'
    FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = b.media_set_id
    WHERE b.database_name = @db AND b.type = 'L'
      AND b.last_lsn > COALESCE(@diff_lsn, @full_lsn)
    UNION ALL
    SELECT 4, '9999-12-31', 'RESTORE DATABASE ' + QUOTENAME(@db) + ' WITH RECOVERY;'
) x
ORDER BY step, dt;
