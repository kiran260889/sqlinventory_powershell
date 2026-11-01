/* SQL Server DBA Scripts - 13. INDEXES (run in the target database)
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  13. INDEXES (run in the target database)
=====================================================================================*/
-- Fragmentation (LIMITED mode, indexes > 1000 pages)
SELECT  OBJECT_SCHEMA_NAME(ips.object_id) + '.' + OBJECT_NAME(ips.object_id) AS table_name,
        i.name AS index_name, i.type_desc, ips.partition_number,
        CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,2)) AS frag_pct,
        ips.page_count, i.fill_factor,
        CASE WHEN ips.avg_fragmentation_in_percent >= 30 THEN 'REBUILD'
             WHEN ips.avg_fragmentation_in_percent >= 10 THEN 'REORGANIZE'
             ELSE 'OK' END AS recommendation
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
WHERE ips.page_count > 1000 AND i.index_id > 0
ORDER BY frag_pct DESC;

-- Missing indexes (review - don't create blindly)
SELECT TOP (50)
        DB_NAME(mid.database_id) AS database_name, mid.statement AS table_name,
        CAST(migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) AS DECIMAL(18,0)) AS improvement_score,
        migs.user_seeks, migs.user_scans, migs.avg_user_impact, migs.last_user_seek,
        mid.equality_columns, mid.inequality_columns, mid.included_columns,
        'CREATE NONCLUSTERED INDEX [IX_' + OBJECT_NAME(mid.object_id, mid.database_id) + '_'
          + CAST(mig.index_group_handle AS VARCHAR(10)) + '] ON ' + mid.statement + ' ('
          + ISNULL(mid.equality_columns,'')
          + CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ',' ELSE '' END
          + ISNULL(mid.inequality_columns,'') + ')'
          + ISNULL(' INCLUDE (' + mid.included_columns + ')','') + ';' AS create_statement
FROM sys.dm_db_missing_index_groups mig
JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details mid       ON mid.index_handle = mig.index_handle
WHERE mid.database_id = DB_ID()
ORDER BY improvement_score DESC;

-- Unused / write-heavy indexes (since last restart)
SELECT  OBJECT_SCHEMA_NAME(i.object_id) + '.' + OBJECT_NAME(i.object_id) AS table_name,
        i.name AS index_name, i.type_desc,
        ISNULL(us.user_seeks,0) AS seeks, ISNULL(us.user_scans,0) AS scans,
        ISNULL(us.user_lookups,0) AS lookups, ISNULL(us.user_updates,0) AS updates,
        (SELECT SUM(a.used_pages)*8/1024 FROM sys.partitions p
           JOIN sys.allocation_units a ON a.container_id = p.partition_id
          WHERE p.object_id = i.object_id AND p.index_id = i.index_id) AS size_mb,
        'DROP INDEX ' + QUOTENAME(i.name) + ' ON ' + QUOTENAME(OBJECT_SCHEMA_NAME(i.object_id))
            + '.' + QUOTENAME(OBJECT_NAME(i.object_id)) + ';' AS drop_statement
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us
       ON us.object_id = i.object_id AND us.index_id = i.index_id AND us.database_id = DB_ID()
WHERE OBJECTPROPERTY(i.object_id,'IsUserTable') = 1
  AND i.type_desc = 'NONCLUSTERED' AND i.is_primary_key = 0 AND i.is_unique_constraint = 0
  AND ISNULL(us.user_seeks,0) + ISNULL(us.user_scans,0) + ISNULL(us.user_lookups,0) = 0
ORDER BY updates DESC;

-- Duplicate indexes (same key columns, same order)
WITH ix AS (
    SELECT i.object_id, i.index_id, i.name,
           STUFF((SELECT ',' + c.name + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE '' END
                  FROM sys.index_columns ic JOIN sys.columns c
                    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                  WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
                  ORDER BY ic.key_ordinal FOR XML PATH('')),1,1,'') AS key_cols
    FROM sys.indexes i
    WHERE OBJECTPROPERTY(i.object_id,'IsUserTable') = 1 AND i.index_id > 0
)
SELECT OBJECT_SCHEMA_NAME(a.object_id) + '.' + OBJECT_NAME(a.object_id) AS table_name,
       a.name AS index_1, b.name AS index_2, a.key_cols
FROM ix a JOIN ix b ON a.object_id = b.object_id AND a.key_cols = b.key_cols AND a.index_id < b.index_id
ORDER BY table_name;

-- Heaps (tables without clustered index)
SELECT OBJECT_SCHEMA_NAME(t.object_id) + '.' + t.name AS table_name, p.rows
FROM sys.tables t
JOIN sys.indexes i    ON i.object_id = t.object_id AND i.index_id = 0
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id = 0
ORDER BY p.rows DESC;

-- Disabled indexes
SELECT OBJECT_SCHEMA_NAME(object_id) + '.' + OBJECT_NAME(object_id) AS table_name, name
FROM sys.indexes WHERE is_disabled = 1;

-- Foreign keys without supporting index
SELECT OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS table_name,
       fk.name AS fk_name, c.name AS column_name
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE NOT EXISTS (SELECT 1 FROM sys.index_columns ic
                  WHERE ic.object_id = fkc.parent_object_id AND ic.column_id = fkc.parent_column_id
                    AND ic.key_ordinal = 1);

-- Untrusted foreign keys / check constraints
SELECT OBJECT_SCHEMA_NAME(parent_object_id) + '.' + OBJECT_NAME(parent_object_id) AS table_name,
       name, 'FK' AS type,
       'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id)) + '.' + QUOTENAME(OBJECT_NAME(parent_object_id))
       + ' WITH CHECK CHECK CONSTRAINT ' + QUOTENAME(name) + ';' AS fix
FROM sys.foreign_keys WHERE is_not_trusted = 1 AND is_disabled = 0
UNION ALL
SELECT OBJECT_SCHEMA_NAME(parent_object_id) + '.' + OBJECT_NAME(parent_object_id), name, 'CHECK',
       'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id)) + '.' + QUOTENAME(OBJECT_NAME(parent_object_id))
       + ' WITH CHECK CHECK CONSTRAINT ' + QUOTENAME(name) + ';'
FROM sys.check_constraints WHERE is_not_trusted = 1 AND is_disabled = 0;
