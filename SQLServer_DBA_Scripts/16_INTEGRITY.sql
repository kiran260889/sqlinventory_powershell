/* SQL Server DBA Scripts - 16. INTEGRITY: DBCC CHECKDB & SUSPECT PAGES
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  16. INTEGRITY: DBCC CHECKDB & SUSPECT PAGES
=====================================================================================*/
-- Last known good CHECKDB per database
DROP TABLE IF EXISTS #dbinfo;
CREATE TABLE #dbinfo (ParentObject VARCHAR(255), [Object] VARCHAR(255), Field VARCHAR(255), [Value] VARCHAR(255));
DROP TABLE IF EXISTS #lastgood;
CREATE TABLE #lastgood (database_name SYSNAME, last_good_checkdb DATETIME);

DECLARE @dbn SYSNAME;
DECLARE dbc CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' AND name <> 'tempdb';
OPEN dbc; FETCH NEXT FROM dbc INTO @dbn;
WHILE @@FETCH_STATUS = 0
BEGIN
    TRUNCATE TABLE #dbinfo;
    INSERT #dbinfo EXEC ('DBCC DBINFO(' + '''' + @dbn + '''' + ') WITH TABLERESULTS, NO_INFOMSGS');
    INSERT #lastgood SELECT @dbn, MAX(TRY_CAST([Value] AS DATETIME)) FROM #dbinfo WHERE Field = 'dbi_dbccLastKnownGood';
    FETCH NEXT FROM dbc INTO @dbn;
END
CLOSE dbc; DEALLOCATE dbc;
SELECT database_name, last_good_checkdb,
       DATEDIFF(DAY, last_good_checkdb, GETDATE()) AS days_ago,
       CASE WHEN last_good_checkdb < DATEADD(DAY,-7,GETDATE()) OR last_good_checkdb = '1900-01-01' THEN 'OVERDUE' ELSE '' END AS alert
FROM #lastgood ORDER BY last_good_checkdb;

-- Suspect pages (any rows here = investigate immediately)
SELECT DB_NAME(database_id) AS database_name, file_id, page_id, event_type, error_count, last_update_date
FROM msdb.dbo.suspect_pages;

/* Run CHECKDB
DBCC CHECKDB (N'YourDB') WITH NO_INFOMSGS, ALL_ERRORMSGS;
DBCC CHECKDB (N'YourDB') WITH PHYSICAL_ONLY, NO_INFOMSGS;          -- lighter, large DBs
DBCC CHECKTABLE (N'dbo.YourTable') WITH NO_INFOMSGS, ALL_ERRORMSGS;
-- Repair is a last resort - restore from backup first. REPAIR_ALLOW_DATA_LOSS loses data.
*/
