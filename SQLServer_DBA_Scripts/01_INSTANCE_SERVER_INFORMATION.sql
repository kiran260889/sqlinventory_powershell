/* SQL Server DBA Scripts - 01. INSTANCE & SERVER INFORMATION
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  01. INSTANCE & SERVER INFORMATION
=====================================================================================*/
SELECT
    SERVERPROPERTY('MachineName')                    AS MachineName,
    SERVERPROPERTY('ServerName')                     AS ServerName,
    SERVERPROPERTY('InstanceName')                   AS InstanceName,
    SERVERPROPERTY('Edition')                        AS Edition,
    SERVERPROPERTY('ProductVersion')                 AS ProductVersion,
    SERVERPROPERTY('ProductLevel')                   AS ProductLevel,      -- RTM / SPn
    SERVERPROPERTY('ProductUpdateLevel')             AS CU,
    SERVERPROPERTY('Collation')                      AS Collation,
    SERVERPROPERTY('IsClustered')                    AS IsClustered,
    SERVERPROPERTY('IsHadrEnabled')                  AS IsHadrEnabled,
    SERVERPROPERTY('IsIntegratedSecurityOnly')       AS WindowsAuthOnly,
    @@VERSION                                        AS FullVersion;

-- Host / hardware
SELECT  cpu_count, hyperthread_ratio, scheduler_count,
        physical_memory_kb/1024           AS physical_memory_mb,
        committed_kb/1024                 AS committed_mb,
        committed_target_kb/1024          AS committed_target_mb,
        sqlserver_start_time,
        DATEDIFF(DAY, sqlserver_start_time, GETDATE()) AS uptime_days,
        virtual_machine_type_desc
FROM sys.dm_os_sys_info;

-- OS info (2017+)
SELECT host_platform, host_distribution, host_release, host_service_pack_level
FROM sys.dm_os_host_info;

-- Service accounts & status
SELECT servicename, service_account, status_desc, startup_type_desc,
       last_startup_time, instant_file_initialization_enabled
FROM sys.dm_server_services;
