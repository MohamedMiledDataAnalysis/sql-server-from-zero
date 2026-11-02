/* SQL Server from Zero — Volume 2
   Chapter 29: Logins, users and roles
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Creates server-level objects (logins nb_analyst, nb_collections, nb_risk,
   nb_auditor, nb_temp, nb_contractor): the clean-up block at the end drops them. */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Start-up clean-up: lets the script run again after an interruption
-- ==============================================================

-- Database principals first (dropping a user removes its memberships)
DROP USER IF EXISTS nb_analyst;
DROP USER IF EXISTS nb_collections;
DROP USER IF EXISTS nb_risk;
DROP USER IF EXISTS nb_auditor;
DROP USER IF EXISTS nb_contractor;
DROP USER IF EXISTS report_service;
GO
IF SCHEMA_ID(N'svc') IS NOT NULL
    ALTER AUTHORIZATION ON SCHEMA::svc TO dbo;
GO
DROP USER IF EXISTS svc_reporting;
DROP SCHEMA IF EXISTS svc;
DROP SCHEMA IF EXISTS risk;
DROP ROLE IF EXISTS branch_reporting;
DROP ROLE IF EXISTS analyst;
DROP ROLE IF EXISTS collections_officer;
DROP ROLE IF EXISTS risk_manager;
DROP ROLE IF EXISTS auditor;
GO
-- Server principals: DROP LOGIN has no IF EXISTS
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_analyst')
    DROP LOGIN nb_analyst;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_collections')
    DROP LOGIN nb_collections;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_collections_team')
    DROP LOGIN nb_collections_team;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_risk')
    DROP LOGIN nb_risk;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_auditor')
    DROP LOGIN nb_auditor;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_temp')
    DROP LOGIN nb_temp;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_contractor')
    DROP LOGIN nb_contractor;
GO


-- ==============================================================
-- 1. Authentication, authorisation and the two levels of identity
-- ==============================================================

SELECT SERVERPROPERTY('IsIntegratedSecurityOnly') AS WindowsOnly,
       SUSER_SNAME() AS MyLogin,     -- the login you connected with
       USER_NAME()   AS MyUser;      -- your user in this database
GO


-- ==============================================================
-- 2. CREATE LOGIN
-- ==============================================================

-- Example passwords for a practice server: real passwords never go in scripts
CREATE LOGIN nb_analyst
    WITH PASSWORD = N'Tq8#Harbour2026!',
         DEFAULT_DATABASE = NorthbridgeLending,
         CHECK_POLICY = ON,
         CHECK_EXPIRATION = OFF;

CREATE LOGIN nb_collections
    WITH PASSWORD = N'Wm4#Granite2026!',
         DEFAULT_DATABASE = NorthbridgeLending,
         CHECK_POLICY = ON,
         CHECK_EXPIRATION = OFF;

CREATE LOGIN nb_risk
    WITH PASSWORD = N'Pz6#Lantern2026!',
         DEFAULT_DATABASE = NorthbridgeLending,
         CHECK_POLICY = ON,
         CHECK_EXPIRATION = OFF;

CREATE LOGIN nb_auditor
    WITH PASSWORD = N'Hd3#Meadow2026!',
         DEFAULT_DATABASE = NorthbridgeLending,
         CHECK_POLICY = ON,
         CHECK_EXPIRATION = OFF;
GO
-- The four logins ([_] makes the underscore literal in LIKE)
SELECT name, type_desc, default_database_name, is_disabled
FROM sys.server_principals
WHERE name LIKE N'nb[_]%'
ORDER BY name;
GO
-- Their password settings
SELECT name, is_policy_checked, is_expiration_checked
FROM sys.sql_logins
WHERE name LIKE N'nb[_]%'
ORDER BY name;
GO

-- NOT RUN BY THE AUTOMATED TEST: the message depends on the operating
-- system's password policy (error 15118 on Windows; another text on Linux).
-- Uncomment to see a weak password refused.
-- CREATE LOGIN nb_weak WITH PASSWORD = N'abc', CHECK_POLICY = ON;
-- GO

-- NOT RUN BY THE AUTOMATED TEST: needs a Windows domain (or a Linux
-- server joined to Active Directory).
-- CREATE LOGIN [NORTHBRIDGE\Credit-Risk-Team] FROM WINDOWS
--     WITH DEFAULT_DATABASE = NorthbridgeLending;
-- GO

-- NOT RUN BY THE AUTOMATED TEST: password expiration and MUST_CHANGE follow
-- the Windows password policy; run on a Windows instance only.
-- CREATE LOGIN nb_newstarter
--     WITH PASSWORD = N'Vk7#Saffron2026!' MUST_CHANGE,
--          DEFAULT_DATABASE = NorthbridgeLending,
--          CHECK_POLICY = ON,
--          CHECK_EXPIRATION = ON;
-- DROP LOGIN nb_newstarter;
-- GO


-- ==============================================================
-- 3. ALTER LOGIN and DROP LOGIN
-- ==============================================================

ALTER LOGIN nb_analyst
    WITH PASSWORD = N'Tq8#Harbour2027!';   -- reset by an administrator

ALTER LOGIN nb_collections DISABLE;        -- refuses new connections

SELECT name, is_disabled
FROM sys.server_principals
WHERE name = N'nb_collections';
GO
-- Enable again, then rename
ALTER LOGIN nb_collections ENABLE;

ALTER LOGIN nb_collections WITH NAME = nb_collections_team;

SELECT name, is_disabled
FROM sys.server_principals
WHERE name LIKE N'nb[_]collections%'
ORDER BY name;
GO
-- Give the old name back
ALTER LOGIN nb_collections_team WITH NAME = nb_collections;
GO
-- DROP LOGIN, and the pattern that can run twice
CREATE LOGIN nb_temp WITH PASSWORD = N'Rb5#Orchard2026!';

DROP LOGIN nb_temp;

IF EXISTS (SELECT 1 FROM sys.server_principals
           WHERE name = N'nb_temp')
    DROP LOGIN nb_temp;               -- safe to run again
GO


-- ==============================================================
-- 4. CREATE USER, ALTER USER and DROP USER
-- ==============================================================

CREATE USER nb_analyst     FOR LOGIN nb_analyst
    WITH DEFAULT_SCHEMA = dbo;
CREATE USER nb_collections FOR LOGIN nb_collections
    WITH DEFAULT_SCHEMA = dbo;
CREATE USER nb_risk        FOR LOGIN nb_risk
    WITH DEFAULT_SCHEMA = dbo;
CREATE USER nb_auditor     FOR LOGIN nb_auditor
    WITH DEFAULT_SCHEMA = dbo;

CREATE USER report_service WITHOUT LOGIN
    WITH DEFAULT_SCHEMA = dbo;
GO
SELECT name,
       type_desc,
       authentication_type_desc AS AuthType,
       default_schema_name
FROM sys.database_principals
WHERE name LIKE N'nb[_]%'
   OR name = N'report_service'
ORDER BY name;
GO
-- A schema for the risk team, a new default schema, a new name
CREATE SCHEMA risk AUTHORIZATION dbo;
GO

ALTER USER nb_risk WITH DEFAULT_SCHEMA = risk;

ALTER USER report_service WITH NAME = svc_reporting;

SELECT name, default_schema_name
FROM sys.database_principals
WHERE name IN (N'nb_risk', N'svc_reporting')
ORDER BY name;
GO
-- A user who owns a schema cannot be dropped
CREATE SCHEMA svc AUTHORIZATION svc_reporting;
GO
-- Deliberate error 15138
DROP USER svc_reporting;
GO
-- Hand the schema to dbo, then drop the user and the schema
ALTER AUTHORIZATION ON SCHEMA::svc TO dbo;

DROP USER svc_reporting;

DROP SCHEMA svc;
GO


-- ==============================================================
-- 5. Fixed server roles and ALTER SERVER ROLE
-- ==============================================================

SELECT name
FROM sys.server_principals
WHERE type = 'R'                   -- R = role
  AND is_fixed_role = 1
  AND name NOT LIKE N'##%'
ORDER BY name;
GO
ALTER SERVER ROLE dbcreator ADD MEMBER nb_risk;

SELECT IS_SRVROLEMEMBER(N'dbcreator', N'nb_risk') AS IsDbCreator,
       IS_SRVROLEMEMBER(N'sysadmin',  N'nb_risk') AS IsSysadmin;
GO
SELECT r.name AS RoleName,
       m.name AS MemberName
FROM sys.server_role_members AS rm
INNER JOIN sys.server_principals AS r
    ON r.principal_id = rm.role_principal_id
INNER JOIN sys.server_principals AS m
    ON m.principal_id = rm.member_principal_id
WHERE m.name LIKE N'nb[_]%'
ORDER BY RoleName, MemberName;
GO
ALTER SERVER ROLE dbcreator DROP MEMBER nb_risk;

SELECT IS_SRVROLEMEMBER(N'dbcreator', N'nb_risk') AS IsDbCreator;
GO


-- ==============================================================
-- 6. Fixed database roles and your own roles
-- ==============================================================

SELECT name
FROM sys.database_principals
WHERE is_fixed_role = 1
  AND name NOT LIKE N'##%'
ORDER BY name;
GO
-- The auditor reads everything and changes nothing
ALTER ROLE db_datareader     ADD MEMBER nb_auditor;
ALTER ROLE db_denydatawriter ADD MEMBER nb_auditor;
GO
-- A role of your own
CREATE ROLE branch_reporting AUTHORIZATION dbo;
GO
ALTER ROLE branch_reporting ADD MEMBER nb_analyst;
ALTER ROLE branch_reporting ADD MEMBER nb_risk;

SELECT r.name AS RoleName,
       m.name AS MemberName
FROM sys.database_role_members AS rm
INNER JOIN sys.database_principals AS r
    ON r.principal_id = rm.role_principal_id
INNER JOIN sys.database_principals AS m
    ON m.principal_id = rm.member_principal_id
WHERE m.name LIKE N'nb[_]%'
ORDER BY RoleName, MemberName;
GO
-- Deliberate error 15144: the role still has members
DROP ROLE branch_reporting;
GO
-- Remove the members first
ALTER ROLE branch_reporting DROP MEMBER nb_analyst;
ALTER ROLE branch_reporting DROP MEMBER nb_risk;

DROP ROLE branch_reporting;
GO


-- ==============================================================
-- 7. Testing as another principal: EXECUTE AS and REVERT
-- ==============================================================

EXECUTE AS LOGIN = N'nb_auditor';

SELECT SUSER_SNAME()                   AS CurrentLogin,
       USER_NAME()                     AS CurrentUser,
       ORIGINAL_LOGIN()                AS OriginalLogin,
       IS_SRVROLEMEMBER(N'sysadmin')   AS IsSysadmin,
       IS_ROLEMEMBER(N'db_datareader') AS IsReader;

SELECT COUNT(*) AS Branches
FROM dbo.Branch;

REVERT;
GO
-- Deliberate error 229: db_denydatawriter refuses the UPDATE
EXECUTE AS USER = N'nb_auditor';

UPDATE dbo.Branch
SET City = City                    -- would change nothing
WHERE BranchID = 1;

REVERT;
GO
-- Safety net for the automated run: never stay impersonated
IF SUSER_SNAME() <> ORIGINAL_LOGIN() REVERT;
GO
SELECT USER_NAME() AS CurrentUser;
GO


-- ==============================================================
-- 8. Orphaned users and ALTER USER ... WITH LOGIN
-- ==============================================================

CREATE LOGIN nb_contractor WITH PASSWORD = N'Fy2#Beacon2026!';

CREATE USER nb_contractor FOR LOGIN nb_contractor;

DROP LOGIN nb_contractor;          -- the user stays behind
GO
-- Users that need a login and have none
SELECT dp.name AS OrphanedUser
FROM sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp
    ON sp.sid = dp.sid
WHERE dp.type = 'S'                              -- SQL user
  AND dp.authentication_type_desc = N'INSTANCE'  -- needs a login
  AND sp.sid IS NULL                             -- none found
ORDER BY dp.name;
GO
-- A new login has a new SID: re-link the user
CREATE LOGIN nb_contractor WITH PASSWORD = N'Fy2#Beacon2027!';

ALTER USER nb_contractor WITH LOGIN = nb_contractor;  -- copy the SID
GO
-- The orphan query again: no rows
SELECT dp.name AS OrphanedUser
FROM sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp
    ON sp.sid = dp.sid
WHERE dp.type = 'S'
  AND dp.authentication_type_desc = N'INSTANCE'
  AND sp.sid IS NULL
ORDER BY dp.name;
GO
-- Remove the contractor
DROP USER IF EXISTS nb_contractor;

IF EXISTS (SELECT 1 FROM sys.server_principals
           WHERE name = N'nb_contractor')
    DROP LOGIN nb_contractor;
GO


-- ==============================================================
-- Applied example: Northbridge's access model, first version
-- ==============================================================

-- Step 1. The four team roles
CREATE ROLE analyst             AUTHORIZATION dbo;
CREATE ROLE collections_officer AUTHORIZATION dbo;
CREATE ROLE risk_manager        AUTHORIZATION dbo;
CREATE ROLE auditor             AUTHORIZATION dbo;
GO
-- Step 2. Fixed roles for each team role
ALTER ROLE db_datareader     ADD MEMBER analyst;
ALTER ROLE db_datareader     ADD MEMBER collections_officer;
ALTER ROLE db_datawriter     ADD MEMBER collections_officer;
ALTER ROLE db_datareader     ADD MEMBER risk_manager;
ALTER ROLE db_datareader     ADD MEMBER auditor;
ALTER ROLE db_denydatawriter ADD MEMBER auditor;
GO
-- Step 3. Each person in their team, and only there
ALTER ROLE db_datareader     DROP MEMBER nb_auditor;
ALTER ROLE db_denydatawriter DROP MEMBER nb_auditor;

ALTER ROLE analyst             ADD MEMBER nb_analyst;
ALTER ROLE collections_officer ADD MEMBER nb_collections;
ALTER ROLE risk_manager        ADD MEMBER nb_risk;
ALTER ROLE auditor             ADD MEMBER nb_auditor;
GO
-- Step 4. Inventory: user, login, roles
SELECT dp.name AS UserName,
       sp.name AS LoginName,
       STRING_AGG(r.name, N', ')
           WITHIN GROUP (ORDER BY r.name) AS Roles
FROM sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp
    ON sp.sid = dp.sid
LEFT JOIN sys.database_role_members AS rm
    ON rm.member_principal_id = dp.principal_id
LEFT JOIN sys.database_principals AS r
    ON r.principal_id = rm.role_principal_id
WHERE dp.name LIKE N'nb[_]%'
GROUP BY dp.name, sp.name
ORDER BY dp.name;
GO
-- Step 5. What each team role inherits
SELECT r.name AS FixedRole,
       m.name AS TeamRole
FROM sys.database_role_members AS rm
INNER JOIN sys.database_principals AS r
    ON r.principal_id = rm.role_principal_id
INNER JOIN sys.database_principals AS m
    ON m.principal_id = rm.member_principal_id
WHERE m.type = 'R'                       -- members that are roles
ORDER BY FixedRole, TeamRole;
GO
-- Step 6. Test two teams
EXECUTE AS LOGIN = N'nb_analyst';

SELECT COUNT(*) AS ArrearsLoans
FROM dbo.Loan
WHERE LoanStatus = N'Arrears';

REVERT;
GO
-- Deliberate error 229: the auditor may not delete
EXECUTE AS LOGIN = N'nb_auditor';

DELETE FROM dbo.Payment
WHERE PaymentID = 0;               -- no such payment

REVERT;
GO
-- Safety net for the automated run: never stay impersonated
IF SUSER_SNAME() <> ORIGINAL_LOGIN() REVERT;
GO


-- ==============================================================
-- Step 7. Clean-up: users, roles, schema, then the logins
-- ==============================================================

DROP USER IF EXISTS nb_analyst;
DROP USER IF EXISTS nb_collections;
DROP USER IF EXISTS nb_risk;
DROP USER IF EXISTS nb_auditor;
GO
DROP ROLE IF EXISTS analyst;
DROP ROLE IF EXISTS collections_officer;
DROP ROLE IF EXISTS risk_manager;
DROP ROLE IF EXISTS auditor;
DROP SCHEMA IF EXISTS risk;
GO
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_analyst')
    DROP LOGIN nb_analyst;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_collections')
    DROP LOGIN nb_collections;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_risk')
    DROP LOGIN nb_risk;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_auditor')
    DROP LOGIN nb_auditor;
GO
-- Nothing left at server level
SELECT COUNT(*) AS LoginsLeft
FROM sys.server_principals
WHERE name LIKE N'nb[_]%';
GO
