/* SQL Server DBA Scripts - 29. KILL / SINGLE-USER / EMERGENCY TEMPLATES   [CHANGES DATA]
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  29. KILL / SINGLE-USER / EMERGENCY TEMPLATES   [CHANGES DATA]
=====================================================================================*/
/*
-- Kill a session (check what it's doing first - rollback can take as long as the work)
KILL 123;
KILL 123 WITH STATUSONLY;   -- rollback progress

-- Generate KILL for all user sessions in a database
SELECT 'KILL ' + CAST(session_id AS VARCHAR(10)) + ';'
FROM sys.dm_exec_sessions WHERE database_id = DB_ID(N'YourDB') AND session_id <> @@SPID;

-- Single-user / back to multi-user
ALTER DATABASE [YourDB] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [YourDB] SET MULTI_USER;

-- Offline / online / read-only
ALTER DATABASE [YourDB] SET OFFLINE WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [YourDB] SET ONLINE;
ALTER DATABASE [YourDB] SET READ_ONLY WITH ROLLBACK IMMEDIATE;

-- Change recovery model / owner / compat level
ALTER DATABASE [YourDB] SET RECOVERY FULL;          -- take a full backup afterwards
ALTER AUTHORIZATION ON DATABASE::[YourDB] TO [sa];
ALTER DATABASE [YourDB] SET COMPATIBILITY_LEVEL = 160;

-- Enable RCSI
ALTER DATABASE [YourDB] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;

-- Move a user database file (set path, take offline, move file at OS, bring online)
ALTER DATABASE [YourDB] MODIFY FILE (NAME = N'YourDB', FILENAME = N'E:\Data\YourDB.mdf');

-- Detach / attach
EXEC sp_detach_db @dbname = N'YourDB';
CREATE DATABASE [YourDB] ON (FILENAME = N'E:\Data\YourDB.mdf'), (FILENAME = N'F:\Log\YourDB_log.ldf') FOR ATTACH;

-- Database in SUSPECT / RECOVERY_PENDING (last resort - restore from backup is preferred)
ALTER DATABASE [YourDB] SET EMERGENCY;
DBCC CHECKDB (N'YourDB') WITH NO_INFOMSGS, ALL_ERRORMSGS;

-- Connect via Dedicated Admin Connection: in SSMS use server name  ADMIN:ServerName
*/
