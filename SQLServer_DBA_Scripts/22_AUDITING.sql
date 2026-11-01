/* SQL Server DBA Scripts - 22. AUDITING: SYSADMINS, FAILED LOGINS, SCHEMA CHANGES
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  22. AUDITING: SYSADMINS, FAILED LOGINS, SCHEMA CHANGES
=====================================================================================*/
-- Who has sysadmin
SELECT m.name, m.type_desc, m.is_disabled
FROM sys.server_role_members rm
JOIN sys.server_principals m ON m.principal_id = rm.member_principal_id
WHERE rm.role_principal_id = SUSER_ID('sysadmin');

-- Failed logins from error log (last 7 days)
EXEC sys.xp_readerrorlog 0, 1, N'Login failed', NULL, NULL, NULL, N'DESC';

-- Recent DDL changes (default trace)
DECLARE @trc2 NVARCHAR(260) = (SELECT path FROM sys.traces WHERE is_default = 1);
SELECT t.StartTime, te.name AS event, t.DatabaseName, t.ObjectName, t.LoginName, t.HostName, t.ApplicationName
FROM sys.fn_trace_gettable(@trc2, DEFAULT) t
JOIN sys.trace_events te ON te.trace_event_id = t.EventClass
WHERE te.name IN ('Object:Created','Object:Deleted','Object:Altered')
  AND t.DatabaseName <> 'tempdb'
ORDER BY t.StartTime DESC;

-- Recently modified objects (current DB)
SELECT TOP (50) SCHEMA_NAME(schema_id) + '.' + name AS object_name, type_desc, create_date, modify_date
FROM sys.objects WHERE is_ms_shipped = 0
ORDER BY modify_date DESC;

-- Server audits & specifications
SELECT a.name, a.type_desc, a.on_failure_desc, a.is_state_enabled, s.status_desc, s.audit_file_path
FROM sys.server_audits a LEFT JOIN sys.dm_server_audit_status s ON s.audit_id = a.audit_id;
