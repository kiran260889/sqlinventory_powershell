/* SQL Server DBA Scripts - 25. ERROR LOG
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  25. ERROR LOG
=====================================================================================*/
-- List error log files
EXEC sys.sp_enumerrorlogs;

-- Search current log (0 = current, 1 = SQL log, 2 = Agent log)
EXEC sys.xp_readerrorlog 0, 1, N'error',   NULL, NULL, NULL, N'DESC';
EXEC sys.xp_readerrorlog 0, 1, N'severity', NULL, NULL, NULL, N'DESC';
EXEC sys.xp_readerrorlog 0, 1, N'I/O requests taking longer', NULL, NULL, NULL, N'DESC';
EXEC sys.xp_readerrorlog 0, 1, N'deadlock', NULL, NULL, NULL, N'DESC';
EXEC sys.xp_readerrorlog 0, 2, NULL, NULL, NULL, NULL, N'DESC';   -- Agent log

/* [CHANGES DATA] Cycle the error log (schedule weekly)
EXEC sys.sp_cycle_errorlog;
EXEC msdb.dbo.sp_cycle_agent_errorlog;
*/
