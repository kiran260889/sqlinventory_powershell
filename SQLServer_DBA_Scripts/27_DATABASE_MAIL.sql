/* SQL Server DBA Scripts - 27. DATABASE MAIL
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  27. DATABASE MAIL
=====================================================================================*/
SELECT TOP (50) mailitem_id, recipients, subject, sent_status, send_request_date, sent_date
FROM msdb.dbo.sysmail_allitems ORDER BY send_request_date DESC;

SELECT TOP (50) l.log_date, l.description, i.recipients, i.subject
FROM msdb.dbo.sysmail_event_log l
LEFT JOIN msdb.dbo.sysmail_allitems i ON i.mailitem_id = l.mailitem_id
WHERE l.event_type = 'error'
ORDER BY l.log_date DESC;

EXEC msdb.dbo.sysmail_help_status_sp;

/* Test mail
EXEC msdb.dbo.sp_send_dbmail @profile_name = N'DBA', @recipients = N'dba@example.com',
     @subject = N'Test from SQL Server', @body = N'Database Mail is working.';
EXEC msdb.dbo.sysmail_start_sp;
*/

-- Operators & alerts
SELECT name, enabled, email_address FROM msdb.dbo.sysoperators;
SELECT name, enabled, severity, message_id, has_notification, last_occurrence_date
FROM msdb.dbo.sysalerts;

/* [CHANGES CONFIG] Standard severity 17-25 + 823/824/825 alerts
DECLARE @op SYSNAME = N'DBA Team', @sev INT = 17, @an SYSNAME;
WHILE @sev <= 25
BEGIN
    SET @an = N'Severity ' + CAST(@sev AS NVARCHAR(3));
    EXEC msdb.dbo.sp_add_alert @name = @an, @severity = @sev, @delay_between_responses = 60, @include_event_description_in = 1;
    EXEC msdb.dbo.sp_add_notification @alert_name = @an, @operator_name = @op, @notification_method = 1;
    SET @sev += 1;
END
EXEC msdb.dbo.sp_add_alert @name = N'Error 823', @message_id = 823, @delay_between_responses = 60, @include_event_description_in = 1;
EXEC msdb.dbo.sp_add_alert @name = N'Error 824', @message_id = 824, @delay_between_responses = 60, @include_event_description_in = 1;
EXEC msdb.dbo.sp_add_alert @name = N'Error 825', @message_id = 825, @delay_between_responses = 60, @include_event_description_in = 1;
EXEC msdb.dbo.sp_add_notification @alert_name = N'Error 823', @operator_name = @op, @notification_method = 1;
EXEC msdb.dbo.sp_add_notification @alert_name = N'Error 824', @operator_name = @op, @notification_method = 1;
EXEC msdb.dbo.sp_add_notification @alert_name = N'Error 825', @operator_name = @op, @notification_method = 1;
*/
