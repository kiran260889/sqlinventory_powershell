/* SQL Server DBA Scripts - 02. CONFIGURATION
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  02. CONFIGURATION
=====================================================================================*/
-- All non-default / key settings
SELECT name, value, value_in_use, minimum, maximum, is_dynamic, is_advanced, description
FROM sys.configurations
ORDER BY name;

-- Key settings at a glance
SELECT name, value_in_use
FROM sys.configurations
WHERE name IN ('max server memory (MB)','min server memory (MB)',
               'max degree of parallelism','cost threshold for parallelism',
               'optimize for ad hoc workloads','backup compression default',
               'remote admin connections','xp_cmdshell','clr enabled',
               'Database Mail XPs','contained database authentication');

-- Active trace flags
DBCC TRACESTATUS(-1);

/* [CHANGES CONFIG] Common baseline changes - review before running
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 28672;      -- leave 10-20% for OS
EXEC sp_configure 'max degree of parallelism', 8;
EXEC sp_configure 'cost threshold for parallelism', 50;
EXEC sp_configure 'optimize for ad hoc workloads', 1;
EXEC sp_configure 'backup compression default', 1;
EXEC sp_configure 'remote admin connections', 1;         -- enables remote DAC
RECONFIGURE;
*/
