/* SQL Server DBA Scripts - 03. DATABASES: STATUS, SIZE, FILES, GROWTH
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  03. DATABASES: STATUS, SIZE, FILES, GROWTH
=====================================================================================*/
-- Database overview
SELECT  d.name, d.database_id, d.state_desc, d.recovery_model_desc,
        d.compatibility_level, d.user_access_desc, d.is_read_only,
        d.page_verify_option_desc, d.is_auto_close_on, d.is_auto_shrink_on,
        d.is_auto_create_stats_on, d.is_auto_update_stats_on,
        d.snapshot_isolation_state_desc, d.is_read_committed_snapshot_on,
        d.is_encrypted, d.is_query_store_on, d.log_reuse_wait_desc,
        SUSER_SNAME(d.owner_sid) AS owner, d.create_date
FROM sys.databases d
ORDER BY d.name;

-- Size per database (data vs log)
SELECT  DB_NAME(database_id) AS database_name,
        CAST(SUM(CASE WHEN type_desc = 'ROWS' THEN size END) * 8.0/1024 AS DECIMAL(18,2)) AS data_mb,
        CAST(SUM(CASE WHEN type_desc = 'LOG'  THEN size END) * 8.0/1024 AS DECIMAL(18,2)) AS log_mb,
        CAST(SUM(size) * 8.0/1024/1024 AS DECIMAL(18,2)) AS total_gb
FROM sys.master_files
GROUP BY database_id
ORDER BY total_gb DESC;

-- File details, autogrowth settings (flags % growth and tiny growth)
SELECT  DB_NAME(mf.database_id) AS database_name, mf.name AS logical_name,
        mf.physical_name, mf.type_desc,
        CAST(mf.size*8.0/1024 AS DECIMAL(18,2)) AS size_mb,
        CASE WHEN mf.max_size = -1 THEN 'Unlimited'
             ELSE CAST(CAST(mf.max_size*8.0/1024 AS DECIMAL(18,0)) AS VARCHAR(20)) + ' MB' END AS max_size,
        CASE WHEN mf.is_percent_growth = 1 THEN CAST(mf.growth AS VARCHAR(10)) + ' %'
             ELSE CAST(mf.growth*8/1024 AS VARCHAR(10)) + ' MB' END AS growth,
        CASE WHEN mf.is_percent_growth = 1 THEN 'REVIEW: % growth'
             WHEN mf.growth*8/1024 < 64 AND mf.growth > 0 THEN 'REVIEW: small growth'
             WHEN mf.growth = 0 THEN 'REVIEW: growth disabled' ELSE '' END AS note
FROM sys.master_files mf
ORDER BY database_name, mf.type_desc;

-- Free space inside files of the CURRENT database
SELECT  name AS logical_name, type_desc,
        CAST(size/128.0 AS DECIMAL(18,2))                                    AS size_mb,
        CAST(FILEPROPERTY(name,'SpaceUsed')/128.0 AS DECIMAL(18,2))          AS used_mb,
        CAST((size - FILEPROPERTY(name,'SpaceUsed'))/128.0 AS DECIMAL(18,2)) AS free_mb,
        CAST(100.0*(size - FILEPROPERTY(name,'SpaceUsed'))/NULLIF(size,0) AS DECIMAL(5,2)) AS free_pct
FROM sys.database_files;

-- Largest tables in the current database
SELECT TOP (50)
        s.name + '.' + t.name AS table_name,
        SUM(CASE WHEN p.index_id IN (0,1) THEN p.rows END) AS row_count,
        CAST(SUM(a.total_pages)*8.0/1024 AS DECIMAL(18,2)) AS total_mb,
        CAST(SUM(a.used_pages)*8.0/1024  AS DECIMAL(18,2)) AS used_mb
FROM sys.tables t
JOIN sys.schemas s          ON s.schema_id = t.schema_id
JOIN sys.partitions p       ON p.object_id = t.object_id
JOIN sys.allocation_units a ON a.container_id = p.partition_id
GROUP BY s.name, t.name
ORDER BY total_mb DESC;

-- Autogrowth events from default trace
DECLARE @trc NVARCHAR(260) = (SELECT path FROM sys.traces WHERE is_default = 1);
SELECT  te.name AS event_name, t.DatabaseName, t.FileName, t.StartTime,
        t.Duration/1000 AS duration_ms, (t.IntegerData*8)/1024 AS growth_mb
FROM sys.fn_trace_gettable(@trc, DEFAULT) t
JOIN sys.trace_events te ON te.trace_event_id = t.EventClass
WHERE te.name IN ('Data File Auto Grow','Log File Auto Grow','Data File Auto Shrink','Log File Auto Shrink')
ORDER BY t.StartTime DESC;
