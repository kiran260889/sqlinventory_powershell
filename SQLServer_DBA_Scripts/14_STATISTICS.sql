/* SQL Server DBA Scripts - 14. STATISTICS (run in the target database)
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  14. STATISTICS (run in the target database)
=====================================================================================*/
SELECT  OBJECT_SCHEMA_NAME(s.object_id) + '.' + OBJECT_NAME(s.object_id) AS table_name,
        s.name AS stats_name, s.auto_created, s.user_created, s.no_recompute,
        sp.last_updated, sp.rows, sp.rows_sampled,
        CAST(100.0*sp.rows_sampled/NULLIF(sp.rows,0) AS DECIMAL(5,2)) AS sample_pct,
        sp.modification_counter,
        CAST(100.0*sp.modification_counter/NULLIF(sp.rows,0) AS DECIMAL(9,2)) AS mod_pct
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECTPROPERTY(s.object_id,'IsUserTable') = 1
ORDER BY sp.modification_counter DESC;

/* [CHANGES DATA]
UPDATE STATISTICS dbo.YourTable WITH FULLSCAN;
UPDATE STATISTICS dbo.YourTable IX_YourIndex WITH SAMPLE 50 PERCENT;
EXEC sp_updatestats;   -- all stats in current DB with modifications
*/
