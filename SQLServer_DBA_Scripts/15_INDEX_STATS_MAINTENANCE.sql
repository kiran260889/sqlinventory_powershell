/* SQL Server DBA Scripts - 15. INDEX & STATS MAINTENANCE (dynamic, current database)
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  15. INDEX & STATS MAINTENANCE (dynamic, current database)
     For production, Ola Hallengren's MaintenanceSolution is the standard choice.
=====================================================================================*/
DECLARE @Execute BIT = 0;   -- 0 = print only, 1 = execute  [CHANGES DATA when 1]
DECLARE @sql NVARCHAR(MAX);
DECLARE @online NVARCHAR(20) =
    CASE WHEN SERVERPROPERTY('EngineEdition') IN (3,5,8) THEN N'ONLINE = ON, ' ELSE N'' END;

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
SELECT CASE WHEN ips.avg_fragmentation_in_percent >= 30
            THEN N'ALTER INDEX ' + QUOTENAME(i.name) + N' ON ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name)
                 + N' REBUILD' + CASE WHEN p.cnt > 1 THEN N' PARTITION = ' + CAST(ips.partition_number AS NVARCHAR(10)) ELSE N'' END
                 + N' WITH (' + @online + N'SORT_IN_TEMPDB = ON, MAXDOP = 4);'
            ELSE N'ALTER INDEX ' + QUOTENAME(i.name) + N' ON ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name)
                 + N' REORGANIZE' + CASE WHEN p.cnt > 1 THEN N' PARTITION = ' + CAST(ips.partition_number AS NVARCHAR(10)) ELSE N'' END + N';'
       END
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
JOIN sys.objects o ON o.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
CROSS APPLY (SELECT COUNT(*) AS cnt FROM sys.partitions WHERE object_id = i.object_id AND index_id = i.index_id) p
WHERE ips.avg_fragmentation_in_percent >= 10 AND ips.page_count > 1000
  AND i.index_id > 0 AND o.is_ms_shipped = 0 AND i.is_disabled = 0;

OPEN c; FETCH NEXT FROM c INTO @sql;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT @sql;
    IF @Execute = 1 EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM c INTO @sql;
END
CLOSE c; DEALLOCATE c;
