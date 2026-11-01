/* SQL Server DBA Scripts - 26. DEADLOCKS (system_health Extended Events session)
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  26. DEADLOCKS (system_health Extended Events session)
=====================================================================================*/
WITH xe AS (
    SELECT CAST(event_data AS XML) AS ed
    FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
    WHERE object_name = 'xml_deadlock_report'
)
SELECT ed.value('(event/@timestamp)[1]','datetime2') AS deadlock_utc,
       ed.query('(event/data/value/deadlock)[1]')    AS deadlock_graph   -- save as .xdl to view
FROM xe
ORDER BY deadlock_utc DESC;

-- Extended Events sessions currently running
SELECT s.name, s.create_time, t.target_name
FROM sys.dm_xe_sessions s JOIN sys.dm_xe_session_targets t ON t.event_session_address = s.address;
