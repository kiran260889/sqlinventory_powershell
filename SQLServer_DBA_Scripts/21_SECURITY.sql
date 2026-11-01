/* SQL Server DBA Scripts - 21. SECURITY: LOGINS, ROLES, PERMISSIONS, ORPHANED USERS
   Target: SQL Server 2016+. Run statements individually.
   Read-only unless marked [CHANGES DATA] or [CHANGES CONFIG]. */

/*=====================================================================================
  21. SECURITY: LOGINS, ROLES, PERMISSIONS, ORPHANED USERS
=====================================================================================*/
-- Server logins
SELECT  sp.name, sp.type_desc, sp.is_disabled, sp.create_date, sp.modify_date,
        sp.default_database_name,
        LOGINPROPERTY(sp.name,'PasswordLastSetTime') AS pwd_last_set,
        LOGINPROPERTY(sp.name,'IsLocked')            AS is_locked,
        LOGINPROPERTY(sp.name,'IsExpired')           AS is_expired,
        sl.is_policy_checked, sl.is_expiration_checked
FROM sys.server_principals sp
LEFT JOIN sys.sql_logins sl ON sl.principal_id = sp.principal_id
WHERE sp.type IN ('S','U','G') AND sp.name NOT LIKE '##%'
ORDER BY sp.name;

-- Server role membership
SELECT r.name AS server_role, m.name AS member, m.type_desc
FROM sys.server_role_members rm
JOIN sys.server_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.server_principals m ON m.principal_id = rm.member_principal_id
ORDER BY r.name, m.name;

-- Server-level permissions (CONTROL SERVER etc.)
SELECT pr.name AS grantee, pe.permission_name, pe.state_desc
FROM sys.server_permissions pe
JOIN sys.server_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name NOT LIKE '##%' AND pe.permission_name NOT IN ('CONNECT SQL','VIEW ANY DATABASE')
ORDER BY pr.name;

-- Database users & role membership (current DB)
SELECT dp.name AS user_name, dp.type_desc, dp.authentication_type_desc,
       SUSER_SNAME(dp.sid) AS login_name,
       STUFF((SELECT ', ' + r.name FROM sys.database_role_members rm
              JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
              WHERE rm.member_principal_id = dp.principal_id FOR XML PATH('')),1,2,'') AS roles
FROM sys.database_principals dp
WHERE dp.type IN ('S','U','G','E','X') AND dp.name NOT IN ('dbo','guest','INFORMATION_SCHEMA','sys')
ORDER BY dp.name;

-- Explicit object permissions (current DB)
SELECT  pr.name AS grantee, pe.class_desc, pe.permission_name, pe.state_desc,
        OBJECT_SCHEMA_NAME(pe.major_id) + '.' + OBJECT_NAME(pe.major_id) AS object_name
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name NOT IN ('public','guest') OR pe.class = 1
ORDER BY pr.name;

-- Orphaned users (current DB) + fix statement
SELECT dp.name AS orphaned_user, dp.type_desc,
       CASE WHEN EXISTS (SELECT 1 FROM sys.server_principals sp WHERE sp.name = dp.name)
            THEN 'ALTER USER ' + QUOTENAME(dp.name) + ' WITH LOGIN = ' + QUOTENAME(dp.name) + ';'
            ELSE '-- no matching login: create login or drop user' END AS fix
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON sp.sid = dp.sid
WHERE dp.type IN ('S','U','G') AND sp.sid IS NULL
  AND dp.authentication_type_desc IN ('INSTANCE','WINDOWS')
  AND dp.name NOT IN ('dbo','guest','INFORMATION_SCHEMA','sys');

-- Guest user enabled in user databases (should be disabled except master/tempdb/msdb)
SELECT DB_NAME() AS database_name, dp.name, pe.permission_name, pe.state_desc
FROM sys.database_permissions pe
JOIN sys.database_principals dp ON dp.principal_id = pe.grantee_principal_id
WHERE dp.name = 'guest' AND pe.permission_name = 'CONNECT' AND pe.state = 'G';

/* [CHANGES CONFIG] Common security tasks
CREATE LOGIN [DOMAIN\User] FROM WINDOWS WITH DEFAULT_DATABASE = [master];
CREATE LOGIN [app_login] WITH PASSWORD = N'<strong password>', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
USE [YourDB];
CREATE USER [app_login] FOR LOGIN [app_login];
ALTER ROLE db_datareader ADD MEMBER [app_login];
ALTER ROLE db_datawriter ADD MEMBER [app_login];
GRANT EXECUTE ON SCHEMA::dbo TO [app_login];
ALTER LOGIN [app_login] ENABLE;   ALTER LOGIN [app_login] DISABLE;
ALTER LOGIN [app_login] WITH PASSWORD = N'<new password>' UNLOCK;
REVOKE CONNECT FROM guest;
*/

-- Script out SQL logins with SID & password hash (for migration / AG secondaries)
SELECT 'CREATE LOGIN ' + QUOTENAME(name)
     + ' WITH PASSWORD = ' + CONVERT(VARCHAR(512), CAST(LOGINPROPERTY(name,'PasswordHash') AS VARBINARY(256)), 1) + ' HASHED'
     + ', SID = ' + CONVERT(VARCHAR(100), sid, 1)
     + ', DEFAULT_DATABASE = ' + QUOTENAME(default_database_name)
     + ', CHECK_POLICY = ' + CASE is_policy_checked WHEN 1 THEN 'ON' ELSE 'OFF' END
     + ', CHECK_EXPIRATION = ' + CASE is_expiration_checked WHEN 1 THEN 'ON' ELSE 'OFF' END + ';' AS create_login
FROM sys.sql_logins
WHERE name NOT LIKE '##%' AND name <> 'sa';
