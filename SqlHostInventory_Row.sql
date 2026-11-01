/*  SqlHostInventory_Row.sql  -  used by Invoke-SqlHostInventory.ps1

    Returns one line per row, wrapped in markers so PowerShell can parse it reliably
    regardless of sqlcmd padding/wrapping:
        <<<ROW>>>col1|col2|...|col26<<<END>>>

    Column order MUST match $InventoryColumns in Invoke-SqlHostInventory.ps1.
    One row per instance; an instance in several AGs returns one row per AG.

    Compatible with SQL Server 2005+ (no inline DECLARE initialisation, version-specific
    DMV columns read via dynamic SQL only when they exist). Columns not available on an
    older version come back empty. SQL Server 2000 is not supported (no sys.* views).

    Permissions: VIEW SERVER STATE; the FQDN domain lookup (xp_regread) normally needs sysadmin.
*/
SET NOCOUNT ON;

-- Domain suffix for FQDN ---------------------------------------------------
DECLARE @Domain nvarchar(255);
BEGIN TRY
    EXEC master.dbo.xp_regread
         N'HKEY_LOCAL_MACHINE',
         N'SYSTEM\CurrentControlSet\Services\Tcpip\Parameters',
         N'Domain',
         @Domain OUTPUT;
END TRY
BEGIN CATCH
    SET @Domain = NULL;
END CATCH;

-- OS string parsed from @@VERSION, e.g. "Windows Server 2019 Standard 10.0" -
DECLARE @ver nvarchar(4000), @start int, @end int, @OS nvarchar(512);
SET @ver   = @@VERSION;
SET @start = CHARINDEX(N' on ', @ver);
IF @start > 0
BEGIN
    SET @start = @start + 4;
    SET @end   = CHARINDEX(N' <', @ver, @start);
    IF @end = 0 SET @end = CHARINDEX(NCHAR(10), @ver, @start);
    IF @end = 0 SET @end = LEN(@ver) + 1;
    SET @OS = LTRIM(RTRIM(REPLACE(SUBSTRING(@ver, @start, @end - @start), NCHAR(13), N'')));
END;

-- Version ---------------------------------------------------------------------
DECLARE @pv nvarchar(128), @major int, @VersionName nvarchar(64);
SET @pv    = CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128));
SET @major = CAST(PARSENAME(@pv, 4) AS int);
SET @VersionName = CASE @major
                       WHEN 17 THEN N'SQL Server 2025'
                       WHEN 16 THEN N'SQL Server 2022'
                       WHEN 15 THEN N'SQL Server 2019'
                       WHEN 14 THEN N'SQL Server 2017'
                       WHEN 13 THEN N'SQL Server 2016'
                       WHEN 12 THEN N'SQL Server 2014'
                       WHEN 11 THEN N'SQL Server 2012'
                       WHEN 10 THEN N'SQL Server 2008/2008 R2'
                       WHEN 9  THEN N'SQL Server 2005'
                       ELSE N'Unknown (' + ISNULL(CAST(@major AS nvarchar(10)), N'?') + N')'
                   END;

-- Instance identity -----------------------------------------------------------
DECLARE @Machine nvarchar(128), @Inst nvarchar(128), @Node nvarchar(128), @SrvName nvarchar(256);
SET @Machine = CAST(SERVERPROPERTY('MachineName') AS nvarchar(128));
SET @Inst    = CAST(SERVERPROPERTY('InstanceName') AS nvarchar(128));          -- NULL = default
SET @Node    = CAST(SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS nvarchar(128));
SET @SrvName = CAST(SERVERPROPERTY('ServerName') AS nvarchar(256));            -- HOST or HOST\INST

-- CPU / memory / VM type (only read columns that exist on this version) -------
DECLARE @PhysicalCores int, @LogicalCPU int, @TotalMemMB bigint, @VMType nvarchar(60), @HostType nvarchar(20);

SELECT @LogicalCPU = cpu_count FROM sys.dm_os_sys_info;

IF EXISTS (SELECT 1 FROM sys.all_columns
           WHERE object_id = OBJECT_ID('sys.dm_os_sys_info') AND name = N'cores_per_socket')
    EXEC sp_executesql N'SELECT @c = socket_count * cores_per_socket FROM sys.dm_os_sys_info;',
                       N'@c int OUTPUT', @c = @PhysicalCores OUTPUT;

IF OBJECT_ID('sys.dm_os_sys_memory') IS NOT NULL
    EXEC sp_executesql N'SELECT @m = total_physical_memory_kb / 1024 FROM sys.dm_os_sys_memory;',
                       N'@m bigint OUTPUT', @m = @TotalMemMB OUTPUT;
ELSE IF EXISTS (SELECT 1 FROM sys.all_columns
                WHERE object_id = OBJECT_ID('sys.dm_os_sys_info') AND name = N'physical_memory_in_bytes')
    EXEC sp_executesql N'SELECT @m = physical_memory_in_bytes / 1048576 FROM sys.dm_os_sys_info;',
                       N'@m bigint OUTPUT', @m = @TotalMemMB OUTPUT;

IF EXISTS (SELECT 1 FROM sys.all_columns
           WHERE object_id = OBJECT_ID('sys.dm_os_sys_info') AND name = N'virtual_machine_type_desc')
    EXEC sp_executesql N'SELECT @v = virtual_machine_type_desc FROM sys.dm_os_sys_info;',
                       N'@v nvarchar(60) OUTPUT', @v = @VMType OUTPUT;

SET @HostType = CASE WHEN @VMType IS NULL    THEN N'Unknown'
                     WHEN @VMType = N'NONE'  THEN N'Physical'
                     ELSE N'Virtual' END;

-- Memory config / DB count -----------------------------------------------------
DECLARE @MinMem int, @MaxMem int, @DbCount int;
SELECT @MinMem = CAST(value_in_use AS int) FROM sys.configurations WHERE name = N'min server memory (MB)';
SELECT @MaxMem = CAST(value_in_use AS int) FROM sys.configurations WHERE name = N'max server memory (MB)';
SELECT @DbCount = COUNT(*) FROM sys.databases WHERE database_id > 4;

-- Availability groups (2012+ with HADR enabled) --------------------------------
CREATE TABLE #ag (AGName nvarchar(128) NULL, AGRole nvarchar(60) NULL);
IF @major >= 11 AND CAST(SERVERPROPERTY('IsHadrEnabled') AS int) = 1
    EXEC (N'INSERT #ag (AGName, AGRole)
            SELECT ag.name, ars.role_desc
            FROM sys.dm_hadr_availability_replica_states AS ars
            JOIN sys.availability_groups AS ag ON ag.group_id = ars.group_id
            WHERE ars.is_local = 1;');
IF NOT EXISTS (SELECT 1 FROM #ag) INSERT #ag (AGName, AGRole) VALUES (NULL, NULL);

-- Output -----------------------------------------------------------------------
SELECT CAST(
      N'<<<ROW>>>'
    + ISNULL(@Machine + ISNULL(N'.' + NULLIF(@Domain, N''), N''), N'')                       + N'|'  -- Server Name FQDN
    + ISNULL(@Machine, N'')                                                                    + N'|'  -- ServerName
    + ISNULL(@Node, N'')                                                                       + N'|'  -- PhysicalNodeName
    + ISNULL(@Inst, N'DEFAULT')                                                                + N'|'  -- InstanceName
    + CASE WHEN @Inst IS NULL THEN N'Default' ELSE N'Named' END                                + N'|'  -- InstanceType
    + ISNULL(@SrvName, N'')                                                                    + N'|'  -- SqlInstanceName
    + CASE WHEN @Inst IS NULL THEN N'Default (MSSQLSERVER)' ELSE N'Named (' + @Inst + N')' END + N'|'  -- InstanceDisplay
    + ISNULL(REPLACE(@OS, N'|', N'/'), N'')                                                    + N'|'  -- WindowsOSVersion
    + ISNULL(@pv, N'')                                                                         + N'|'  -- SQLVersionNumber
    + @VersionName                                                                             + N'|'  -- SQLVersionName
    + ISNULL(CAST(SERVERPROPERTY('Edition') AS nvarchar(128)), N'')                            + N'|'  -- SQLEdition
    + ISNULL(CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(128)), N'')                       + N'|'  -- ServicePackLevel
    + ISNULL(CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(128)), N'')                 + N'|'  -- CUBundleLevel
    + ISNULL(CAST(@PhysicalCores AS nvarchar(20)), N'')                                        + N'|'  -- PhysicalCoreCount
    + ISNULL(CAST(@LogicalCPU AS nvarchar(20)), N'')                                           + N'|'  -- LogicalCPUCount
    + ISNULL(CAST(@TotalMemMB AS nvarchar(20)), N'')                                           + N'|'  -- TotalOSMemory_MB
    + ISNULL(CAST(@MinMem AS nvarchar(20)), N'')                                               + N'|'  -- MinServerMemory_MB
    + ISNULL(CAST(@MaxMem AS nvarchar(20)), N'')                                               + N'|'  -- MaxServerMemory_MB
    + ISNULL(REPLACE(a.AGName, N'|', N'/'), N'')                                               + N'|'  -- AGName
    + ISNULL(a.AGRole, N'')                                                                    + N'|'  -- AGRole
    + ISNULL(CAST(@DbCount AS nvarchar(20)), N'')                                              + N'|'  -- TotalDatabaseCount
    + ISNULL(@VMType, N'')                                                                     + N'|'  -- VirtualMachineType
    + @HostType                                                                                + N'|'  -- HostType
    + ISNULL(CAST(SERVERPROPERTY('IsClustered') AS nvarchar(10)), N'')                         + N'|'  -- IsClustered
    + ISNULL(CAST(SERVERPROPERTY('IsHadrEnabled') AS nvarchar(10)), N'')                       + N'|'  -- IsHadrEnabled
    + CONVERT(nvarchar(30), GETDATE(), 120)                                                            -- CollectedAt
    + N'<<<END>>>'
    AS nvarchar(4000))
FROM #ag AS a;

DROP TABLE #ag;
