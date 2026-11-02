/* SQL Server from Zero — Volume 2
   Chapter 29: Logins, users and roles — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Creates server-level logins nb_trainee and nb_trainee_2026: Correction 29.8
   drops them. */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Start-up clean-up: lets the script run again after an interruption
-- ==============================================================

IF DATABASE_PRINCIPAL_ID(N'branch_managers') IS NOT NULL
BEGIN
    IF DATABASE_PRINCIPAL_ID(N'bm_leeds') IS NOT NULL
        ALTER ROLE branch_managers DROP MEMBER bm_leeds;
    IF DATABASE_PRINCIPAL_ID(N'bm_bristol') IS NOT NULL
        ALTER ROLE branch_managers DROP MEMBER bm_bristol;
    DROP ROLE branch_managers;
END;
GO
DROP USER IF EXISTS nb_trainee;
DROP USER IF EXISTS bm_leeds;
DROP USER IF EXISTS bm_bristol;
GO
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_trainee')
    DROP LOGIN nb_trainee;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_trainee_2026')
    DROP LOGIN nb_trainee_2026;
GO


-- ==============================================================
-- Correction 29.1
-- ==============================================================

SELECT SERVERPROPERTY('IsIntegratedSecurityOnly') AS WindowsOnly,
       SUSER_SNAME()                 AS MyLogin,
       USER_NAME()                   AS MyUser,
       IS_SRVROLEMEMBER(N'sysadmin') AS IsSysadmin;
GO


-- ==============================================================
-- Correction 29.2
-- ==============================================================

CREATE LOGIN nb_trainee
    WITH PASSWORD = N'Jc9#Willow2026!',
         DEFAULT_DATABASE = NorthbridgeLending,
         CHECK_POLICY = ON,
         CHECK_EXPIRATION = OFF;
GO
SELECT name,
       default_database_name,
       is_policy_checked,                  -- CHECK_POLICY
       is_expiration_checked               -- CHECK_EXPIRATION
FROM sys.sql_logins
WHERE name = N'nb_trainee';
GO


-- ==============================================================
-- Correction 29.3
-- ==============================================================

CREATE USER nb_trainee FOR LOGIN nb_trainee
    WITH DEFAULT_SCHEMA = dbo;

ALTER ROLE db_datareader ADD MEMBER nb_trainee;
GO
SELECT IS_ROLEMEMBER(N'db_datareader', N'nb_trainee') AS IsReader,
       IS_ROLEMEMBER(N'db_datawriter', N'nb_trainee') AS IsWriter;
GO


-- ==============================================================
-- Correction 29.4
-- ==============================================================

ALTER LOGIN nb_trainee DISABLE;

SELECT name, is_disabled
FROM sys.server_principals
WHERE name = N'nb_trainee';

ALTER LOGIN nb_trainee ENABLE;

ALTER LOGIN nb_trainee WITH NAME = nb_trainee_2026;
GO
SELECT dp.name AS UserName,
       sp.name AS LoginName
FROM sys.database_principals AS dp
INNER JOIN sys.server_principals AS sp
    ON sp.sid = dp.sid                   -- the link is the SID
WHERE dp.name = N'nb_trainee';
GO


-- ==============================================================
-- Correction 29.5
-- ==============================================================

-- Contains deliberate error 229 (INSERT refused); REVERT still runs
EXECUTE AS LOGIN = N'nb_trainee_2026';

SELECT SUSER_SNAME()    AS CurrentLogin,
       USER_NAME()      AS CurrentUser,
       ORIGINAL_LOGIN() AS OriginalLogin;

SELECT COUNT(*) AS DefaultLoans
FROM dbo.Loan
WHERE LoanStatus = N'Default';

INSERT INTO dbo.Branch (BranchID, BranchName, City, Region, OpenedDate)
VALUES (9, N'Test', N'Test', N'Test', '2026-09-30');  -- refused

REVERT;
GO
-- Safety net for the automated run: never stay impersonated
IF SUSER_SNAME() <> ORIGINAL_LOGIN() REVERT;
GO


-- ==============================================================
-- Correction 29.6
-- ==============================================================

CREATE USER bm_leeds   WITHOUT LOGIN;
CREATE USER bm_bristol WITHOUT LOGIN;

CREATE ROLE branch_managers AUTHORIZATION dbo;
GO
ALTER ROLE branch_managers ADD MEMBER bm_leeds;
ALTER ROLE branch_managers ADD MEMBER bm_bristol;

SELECT m.name AS MemberName
FROM sys.database_role_members AS rm
INNER JOIN sys.database_principals AS m
    ON m.principal_id = rm.member_principal_id
WHERE rm.role_principal_id = DATABASE_PRINCIPAL_ID(N'branch_managers')
ORDER BY m.name;

ALTER ROLE branch_managers DROP MEMBER bm_leeds;   -- empty it first
ALTER ROLE branch_managers DROP MEMBER bm_bristol;

DROP ROLE branch_managers;
GO


-- ==============================================================
-- Correction 29.7
-- ==============================================================

DROP LOGIN nb_trainee_2026;
GO
SELECT dp.name AS OrphanedUser
FROM sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp
    ON sp.sid = dp.sid
WHERE dp.type = 'S'
  AND dp.authentication_type_desc = N'INSTANCE'
  AND sp.sid IS NULL;
GO
CREATE LOGIN nb_trainee
    WITH PASSWORD = N'Jc9#Willow2027!',
         DEFAULT_DATABASE = NorthbridgeLending;

ALTER USER nb_trainee WITH LOGIN = nb_trainee;   -- new SID copied
GO
SELECT dp.name AS UserName,
       sp.name AS LoginName,
       IS_ROLEMEMBER(N'db_datareader', dp.name) AS IsReader
FROM sys.database_principals AS dp
INNER JOIN sys.server_principals AS sp
    ON sp.sid = dp.sid
WHERE dp.name = N'nb_trainee';
GO


-- ==============================================================
-- Correction 29.8 (also the clean-up of every exercise)
-- ==============================================================

IF DATABASE_PRINCIPAL_ID(N'branch_managers') IS NOT NULL
BEGIN
    IF DATABASE_PRINCIPAL_ID(N'bm_leeds') IS NOT NULL
        ALTER ROLE branch_managers DROP MEMBER bm_leeds;
    IF DATABASE_PRINCIPAL_ID(N'bm_bristol') IS NOT NULL
        ALTER ROLE branch_managers DROP MEMBER bm_bristol;
    DROP ROLE branch_managers;
END;

DROP USER IF EXISTS nb_trainee;
DROP USER IF EXISTS bm_leeds;
DROP USER IF EXISTS bm_bristol;

IF EXISTS (SELECT 1 FROM sys.server_principals
           WHERE name = N'nb_trainee')
    DROP LOGIN nb_trainee;
IF EXISTS (SELECT 1 FROM sys.server_principals
           WHERE name = N'nb_trainee_2026')
    DROP LOGIN nb_trainee_2026;

SELECT (SELECT COUNT(*) FROM sys.server_principals
        WHERE name IN (N'nb_trainee', N'nb_trainee_2026'))
           AS ServerLeft,
       (SELECT COUNT(*) FROM sys.database_principals
        WHERE name IN (N'nb_trainee', N'bm_leeds', N'bm_bristol',
                       N'branch_managers'))
           AS DatabaseLeft;
GO
