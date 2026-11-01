/* SQL Server DBA Scripts - 23. ALWAYS ON AVAILABILITY GROUPS
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  23. ALWAYS ON AVAILABILITY GROUPS
=====================================================================================*/
-- AG & replica health
SELECT  ag.name AS ag_name, ar.replica_server_name, ars.role_desc,
        ar.availability_mode_desc, ar.failover_mode_desc,
        ars.connected_state_desc, ars.synchronization_health_desc,
        ars.operational_state_desc, ar.secondary_role_allow_connections_desc,
        ar.backup_priority
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar              ON ar.group_id = ag.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ars.replica_id = ar.replica_id
ORDER BY ag.name, ars.role_desc;

-- Database-level sync, send & redo queues, estimated data loss
SELECT  ag.name AS ag_name, ar.replica_server_name, DB_NAME(drs.database_id) AS database_name,
        drs.is_primary_replica, drs.synchronization_state_desc, drs.synchronization_health_desc,
        drs.is_suspended, drs.suspend_reason_desc,
        drs.log_send_queue_size AS send_queue_kb, drs.log_send_rate AS send_rate_kbps,
        drs.redo_queue_size AS redo_queue_kb, drs.redo_rate AS redo_rate_kbps,
        drs.last_commit_time,
        DATEDIFF(SECOND, drs.last_commit_time,
                 MAX(drs.last_commit_time) OVER (PARTITION BY drs.group_id, drs.database_id)) AS lag_seconds,
        CASE WHEN drs.redo_rate > 0 THEN drs.redo_queue_size / drs.redo_rate END AS est_redo_seconds
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON ar.replica_id = drs.replica_id
JOIN sys.availability_groups ag   ON ag.group_id = drs.group_id
ORDER BY ag.name, database_name, ar.replica_server_name;

-- Listeners
SELECT ag.name AS ag_name, l.dns_name, l.port, ip.ip_address, ip.state_desc
FROM sys.availability_group_listeners l
JOIN sys.availability_groups ag ON ag.group_id = l.group_id
LEFT JOIN sys.availability_group_listener_ip_addresses ip ON ip.listener_id = l.listener_id;

-- Is this replica the preferred backup replica?
SELECT d.name, sys.fn_hadr_backup_is_preferred_replica(d.name) AS is_preferred_backup
FROM sys.databases d WHERE d.replica_id IS NOT NULL;

-- Cluster nodes / quorum
SELECT member_name, member_type_desc, member_state_desc, number_of_quorum_votes
FROM sys.dm_hadr_cluster_members;

/* [CHANGES CONFIG] AG operations
ALTER AVAILABILITY GROUP [AG1] FAILOVER;                                -- run on target synchronous secondary
ALTER AVAILABILITY GROUP [AG1] FORCE_FAILOVER_ALLOW_DATA_LOSS;          -- DR only
ALTER DATABASE [YourDB] SET HADR SUSPEND;
ALTER DATABASE [YourDB] SET HADR RESUME;
ALTER AVAILABILITY GROUP [AG1] MODIFY REPLICA ON N'NODE2' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT);
ALTER AVAILABILITY GROUP [AG1] ADD DATABASE [YourDB];
*/
