/* SQL Server DBA Scripts - 04. DISK / VOLUME SPACE
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  04. DISK / VOLUME SPACE
=====================================================================================*/
SELECT DISTINCT
        vs.volume_mount_point, vs.logical_volume_name, vs.file_system_type,
        CAST(vs.total_bytes/1073741824.0 AS DECIMAL(18,2))     AS total_gb,
        CAST(vs.available_bytes/1073741824.0 AS DECIMAL(18,2)) AS free_gb,
        CAST(100.0*vs.available_bytes/vs.total_bytes AS DECIMAL(5,2)) AS free_pct
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
ORDER BY free_pct;
