/* SQL Server DBA Scripts - 20. IO LATENCY PER FILE
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  20. IO LATENCY PER FILE
=====================================================================================*/
SELECT  DB_NAME(vfs.database_id) AS database_name, mf.name AS logical_name, mf.type_desc,
        mf.physical_name,
        vfs.num_of_reads, vfs.num_of_writes,
        CAST(vfs.io_stall_read_ms /NULLIF(vfs.num_of_reads,0)  AS DECIMAL(10,2)) AS avg_read_ms,
        CAST(vfs.io_stall_write_ms/NULLIF(vfs.num_of_writes,0) AS DECIMAL(10,2)) AS avg_write_ms,
        CAST(vfs.num_of_bytes_read/1048576.0    AS DECIMAL(18,0)) AS mb_read,
        CAST(vfs.num_of_bytes_written/1048576.0 AS DECIMAL(18,0)) AS mb_written
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf ON mf.database_id = vfs.database_id AND mf.file_id = vfs.file_id
ORDER BY (vfs.io_stall_read_ms + vfs.io_stall_write_ms) DESC;
-- Rough guide: data reads < 20 ms, log writes < 5 ms
