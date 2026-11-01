/* SQL Server DBA Scripts - 08. SQL AGENT JOBS
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  08. SQL AGENT JOBS
=====================================================================================*/
-- Job inventory with last outcome
SELECT  j.name AS job_name, j.enabled, SUSER_SNAME(j.owner_sid) AS owner,
        c.name AS category,
        CASE h.run_status WHEN 0 THEN 'Failed' WHEN 1 THEN 'Succeeded' WHEN 2 THEN 'Retry'
                          WHEN 3 THEN 'Canceled' WHEN 4 THEN 'In progress' END AS last_status,
        msdb.dbo.agent_datetime(h.run_date, h.run_time) AS last_run,
        STUFF(STUFF(RIGHT('000000' + CAST(h.run_duration AS VARCHAR(6)),6),5,0,':'),3,0,':') AS last_duration
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
OUTER APPLY (SELECT TOP 1 run_status, run_date, run_time, run_duration
             FROM msdb.dbo.sysjobhistory WHERE job_id = j.job_id AND step_id = 0
             ORDER BY run_date DESC, run_time DESC) h
ORDER BY j.name;

-- Failed job steps, last 7 days
SELECT  j.name AS job_name, h.step_id, h.step_name,
        msdb.dbo.agent_datetime(h.run_date, h.run_time) AS run_datetime,
        h.sql_severity, h.message
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE h.run_status = 0
  AND msdb.dbo.agent_datetime(h.run_date, h.run_time) >= DATEADD(DAY,-7,GETDATE())
ORDER BY run_datetime DESC;

-- Currently running jobs
SELECT  j.name AS job_name, ja.start_execution_date,
        DATEDIFF(MINUTE, ja.start_execution_date, GETDATE()) AS running_minutes,
        ja.last_executed_step_id
FROM msdb.dbo.sysjobactivity ja
JOIN msdb.dbo.sysjobs j ON j.job_id = ja.job_id
WHERE ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
  AND ja.start_execution_date IS NOT NULL
  AND ja.stop_execution_date IS NULL;

-- Job schedules
SELECT  j.name AS job_name, s.name AS schedule_name, s.enabled,
        CASE s.freq_type WHEN 1 THEN 'Once' WHEN 4 THEN 'Daily' WHEN 8 THEN 'Weekly'
                         WHEN 16 THEN 'Monthly' WHEN 32 THEN 'Monthly relative'
                         WHEN 64 THEN 'Agent start' WHEN 128 THEN 'Idle' END AS frequency,
        s.freq_interval, s.freq_subday_type, s.freq_subday_interval,
        STUFF(STUFF(RIGHT('000000'+CAST(s.active_start_time AS VARCHAR(6)),6),5,0,':'),3,0,':') AS start_time,
        msdb.dbo.agent_datetime(NULLIF(js.next_run_date,0), js.next_run_time) AS next_run
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules s     ON s.schedule_id = js.schedule_id
ORDER BY j.name;

-- Jobs owned by individual logins (should usually be sa / service account)
SELECT name, SUSER_SNAME(owner_sid) AS owner
FROM msdb.dbo.sysjobs
WHERE SUSER_SNAME(owner_sid) NOT IN ('sa') OR SUSER_SNAME(owner_sid) IS NULL;

/* [CHANGES CONFIG]
EXEC msdb.dbo.sp_start_job  @job_name = N'JobName';
EXEC msdb.dbo.sp_stop_job   @job_name = N'JobName';
EXEC msdb.dbo.sp_update_job @job_name = N'JobName', @enabled = 0;
EXEC msdb.dbo.sp_update_job @job_name = N'JobName', @owner_login_name = N'sa';
*/
