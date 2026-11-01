/* SQL Server DBA Scripts - 24. LOG SHIPPING / MIRRORING / REPLICATION
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  24. LOG SHIPPING / MIRRORING / REPLICATION
=====================================================================================*/
-- Log shipping monitor (run on monitor/primary/secondary)
EXEC master.sys.sp_help_log_shipping_monitor;

SELECT primary_server, primary_database, last_backup_date, backup_threshold
FROM msdb.dbo.log_shipping_monitor_primary;

SELECT secondary_server, secondary_database, last_copied_date, last_restored_date,
       last_restored_latency, restore_threshold
FROM msdb.dbo.log_shipping_monitor_secondary;

-- Database mirroring
SELECT DB_NAME(database_id) AS database_name, mirroring_role_desc, mirroring_state_desc,
       mirroring_safety_level_desc, mirroring_partner_name, mirroring_witness_name, mirroring_witness_state_desc
FROM sys.database_mirroring WHERE mirroring_guid IS NOT NULL;

-- Replication: published / subscribed databases
SELECT name, is_published, is_subscribed, is_merge_published, is_distributor
FROM sys.databases
WHERE is_published = 1 OR is_subscribed = 1 OR is_merge_published = 1 OR is_distributor = 1;

-- Replication agent status (run on distributor)
-- EXEC distribution.dbo.sp_replmonitorhelppublication;
-- EXEC distribution.dbo.sp_replmonitorsubscriptionpendingcmds @publisher, @publisher_db, @publication, @subscriber, @subscriber_db, 0;
