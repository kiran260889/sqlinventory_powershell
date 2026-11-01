/* SQL Server DBA Scripts - 28. HOUSEKEEPING (msdb history cleanup)
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  28. HOUSEKEEPING (msdb history cleanup)
=====================================================================================*/
-- msdb size check
SELECT name, size*8/1024 AS size_mb FROM msdb.sys.database_files;

/* [CHANGES DATA] Purge history older than 60 days
DECLARE @cutoff DATETIME = DATEADD(DAY,-60,GETDATE());
EXEC msdb.dbo.sp_delete_backuphistory @oldest_date = @cutoff;
EXEC msdb.dbo.sp_purge_jobhistory     @oldest_date = @cutoff;
EXEC msdb.dbo.sysmail_delete_mailitems_sp @sent_before = @cutoff;
EXEC msdb.dbo.sysmail_delete_log_sp       @logged_before = @cutoff;
EXEC msdb.dbo.sp_maintplan_delete_log NULL, NULL, @cutoff;
*/
