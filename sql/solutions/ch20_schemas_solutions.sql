/* SQL Server from Zero — Volume 1
   Chapter 20: Schemas and ownership
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Correction 20.1
USE NorthbridgeLending;
GO
SELECT s.name AS SchemaName,
       p.name AS OwnerName          -- owner's name, not number
FROM sys.schemas AS s
INNER JOIN sys.database_principals AS p
    ON p.principal_id = s.principal_id
WHERE s.schema_id < 16384           -- no fixed-role schemas
ORDER BY s.name;
GO

-- Step by step

-- Correction 20.2
-- Run this batch twice: the second run creates nothing
IF SCHEMA_ID(N'audit') IS NULL
    EXEC (N'CREATE SCHEMA audit AUTHORIZATION dbo;');
GO
IF SCHEMA_ID(N'audit') IS NULL
    EXEC (N'CREATE SCHEMA audit AUTHORIZATION dbo;');
GO

SELECT COUNT(*) AS AuditSchemas
FROM sys.schemas
WHERE name = N'audit';
GO

-- Step by step

-- Correction 20.3
SELECT ProductCode, ProductName, ProductType, BaseRate,
       MaxTermMonths, IsSecured
INTO audit.Product                   -- schema-qualified target
FROM dbo.Product;

SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME = N'Product'
ORDER BY TABLE_SCHEMA;
GO

-- Step by step

-- Correction 20.4
CREATE SCHEMA archive AUTHORIZATION dbo;
GO
ALTER SCHEMA archive TRANSFER audit.Product;  -- destination first

SELECT SCHEMA_NAME(schema_id) + N'.' + name AS TwoPartName
FROM sys.tables
WHERE name = N'Product'
ORDER BY TwoPartName;

SELECT COUNT(*) AS ObjectsInAudit             -- 0 = empty
FROM sys.objects
WHERE schema_id = SCHEMA_ID(N'audit');
GO

-- Step by step

-- Correction 20.5
/* Fails on purpose (see the book); commented out so that the
   script runs end to end:
DROP SCHEMA archive;                  -- fails: not empty
*/
GO
DROP TABLE IF EXISTS archive.Product; -- empty the schema
DROP SCHEMA archive;                  -- now succeeds
DROP SCHEMA IF EXISTS archive;        -- nothing to do, no error
GO

-- Step by step

-- Correction 20.6
CREATE USER AuditReader WITHOUT LOGIN
    WITH DEFAULT_SCHEMA = audit;      -- test user, no login

EXECUTE AS USER = N'AuditReader';     -- act as the test user
SELECT USER_NAME()   AS CurrentUser,
       SCHEMA_NAME() AS DefaultSchema;
REVERT;                               -- back to yourself

SELECT USER_NAME()   AS CurrentUser,
       SCHEMA_NAME() AS DefaultSchema;
GO

-- Step by step

-- Correction 20.7
SELECT BranchID, BranchName, City, Region, OpenedDate
INTO audit.Branch
FROM dbo.Branch;

ALTER AUTHORIZATION ON SCHEMA::audit TO AuditReader;

EXECUTE AS USER = N'AuditReader';

SELECT COUNT(*) AS OwnBranchRows      -- resolves to audit.Branch
FROM Branch;

SELECT COUNT(*) AS DboBranchRows      -- explicit dbo: no permission
FROM dbo.Branch;

REVERT;
GO

-- Step by step

-- Correction 20.8
-- Fails on purpose with Msg 15138: AuditReader still owns the audit schema.
-- DROP USER AuditReader;                 -- fails: owns a schema
GO
DROP TABLE IF EXISTS audit.Branch;     -- 1. empty the schema
DROP SCHEMA IF EXISTS audit;           -- 2. drop it
DROP USER IF EXISTS AuditReader;       -- 3. now the user can go

-- Proof: no schema, no user, no table left
SELECT (SELECT COUNT(*) FROM sys.schemas
        WHERE name IN (N'audit', N'archive'))      AS Schemas,
       (SELECT COUNT(*) FROM sys.database_principals
        WHERE name = N'AuditReader')               AS Users,
       (SELECT COUNT(*) FROM sys.tables
        WHERE schema_id IN (SCHEMA_ID(N'audit'),
                            SCHEMA_ID(N'archive'))) AS Tables;
GO

-- Step by step

-- Clean-up: remove everything the exercises created
USE NorthbridgeLending;
GO
IF SCHEMA_ID(N'audit') IS NOT NULL
    ALTER AUTHORIZATION ON SCHEMA::audit TO dbo;
DROP TABLE IF EXISTS audit.Product, audit.Branch, archive.Product;
DROP SCHEMA IF EXISTS audit;
DROP SCHEMA IF EXISTS archive;
DROP SCHEMA IF EXISTS sandbox;
DROP USER IF EXISTS AuditReader;
GO
