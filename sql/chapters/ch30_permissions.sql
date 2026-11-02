/* SQL Server from Zero — Volume 2
   Chapter 30: GRANT, DENY and REVOKE
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022);
   granular UNMASK on a column needs SQL Server 2022 or later.
   Creates the server-level login nb_dba_support: the clean-up block at the end drops it. */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Start-up clean-up: lets the script run again after an interruption
-- ==============================================================

DROP SECURITY POLICY IF EXISTS security.LoanBranchPolicy;
GO
DROP FUNCTION IF EXISTS security.fn_LoanBranchFilter;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS dbo.Practice_UserBranch;
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS sandbox.StressTest;
DROP TABLE IF EXISTS sandbox.AnalystScratch;
DROP VIEW IF EXISTS reporting.vBranchBook;
DROP PROCEDURE IF EXISTS dbo.usp_ArrearsByBranch;
DROP PROCEDURE IF EXISTS dbo.usp_LoansByStatus;
GO
DROP SCHEMA IF EXISTS reporting;
DROP SCHEMA IF EXISTS sandbox;
DROP SCHEMA IF EXISTS security;
GO
-- Grantees before grantors: ben_collections may hold a grant from cara_risk
DROP USER IF EXISTS ben_collections;
DROP USER IF EXISTS amy_analyst;
DROP USER IF EXISTS dan_auditor;
DROP USER IF EXISTS cara_risk;
DROP USER IF EXISTS officer_leeds;
DROP USER IF EXISTS officer_bristol;
GO
-- collections_officer may hold a grant from risk_manager: drop it first
DROP ROLE IF EXISTS collections_officer;
DROP ROLE IF EXISTS analyst;
DROP ROLE IF EXISTS auditor;
DROP ROLE IF EXISTS loan_officer;
DROP ROLE IF EXISTS risk_manager;
GO
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_dba_support')
    DROP LOGIN nb_dba_support;
GO


-- ==============================================================
-- 1. Securables, permissions and GRANT on objects
-- ==============================================================

-- The four team roles, one test user each (chapter 29)
CREATE ROLE analyst             AUTHORIZATION dbo;
CREATE ROLE collections_officer AUTHORIZATION dbo;
CREATE ROLE risk_manager        AUTHORIZATION dbo;
CREATE ROLE auditor             AUTHORIZATION dbo;

CREATE USER amy_analyst     WITHOUT LOGIN;
CREATE USER ben_collections WITHOUT LOGIN;
CREATE USER cara_risk       WITHOUT LOGIN;
CREATE USER dan_auditor     WITHOUT LOGIN;
GO
ALTER ROLE analyst             ADD MEMBER amy_analyst;
ALTER ROLE collections_officer ADD MEMBER ben_collections;
ALTER ROLE risk_manager        ADD MEMBER cara_risk;
ALTER ROLE auditor             ADD MEMBER dan_auditor;
GO
-- Analysts read the reference tables
GRANT SELECT ON dbo.Branch TO analyst;
GRANT SELECT ON OBJECT::dbo.Product TO analyst;   -- same form

EXECUTE AS USER = N'amy_analyst';

SELECT COUNT(*) AS Branches
FROM dbo.Branch;

SELECT HAS_PERMS_BY_NAME(N'dbo.Branch', N'OBJECT', N'SELECT')
           AS ReadBranch,
       HAS_PERMS_BY_NAME(N'dbo.Loan', N'OBJECT', N'SELECT')
           AS ReadLoan,
       HAS_PERMS_BY_NAME(N'dbo.Branch', N'OBJECT', N'UPDATE')
           AS UpdateBranch;

REVERT;
GO


-- ==============================================================
-- 2. Permissions on columns, schemas, the database and the server
-- ==============================================================

-- Columns
GRANT SELECT ON dbo.Customer
    (CustomerID, FirstName, LastName, Phone, City)
    TO collections_officer;

EXECUTE AS USER = N'ben_collections';

SELECT CustomerID, FirstName, LastName, Phone
FROM dbo.Customer
WHERE CustomerID IN (1, 2, 3)
ORDER BY CustomerID;

SELECT HAS_PERMS_BY_NAME(N'dbo.Customer', N'OBJECT', N'SELECT')
           AS WholeTable,
       HAS_PERMS_BY_NAME(N'dbo.Customer', N'OBJECT', N'SELECT',
                         N'Phone', N'COLUMN') AS PhoneColumn,
       HAS_PERMS_BY_NAME(N'dbo.Customer', N'OBJECT', N'SELECT',
                         N'AnnualIncome', N'COLUMN') AS IncomeColumn;

REVERT;
GO
-- Deliberate error 230: SELECT * names columns that are not granted
EXECUTE AS USER = N'ben_collections';

SELECT *
FROM dbo.Customer
WHERE CustomerID = 1;

REVERT;
GO
-- Safety net for the automated run: never stay impersonated
IF USER_NAME() <> N'dbo' REVERT;
GO

-- Schemas
CREATE SCHEMA reporting AUTHORIZATION dbo;
GO

CREATE OR ALTER VIEW reporting.vBranchBook
AS
SELECT b.BranchName,
       COUNT(*)                  AS Loans,
       SUM(l.OutstandingBalance) AS Outstanding
FROM dbo.Loan AS l
INNER JOIN dbo.Branch AS b
    ON b.BranchID = l.BranchID
GROUP BY b.BranchName;
GO

GRANT SELECT ON SCHEMA::reporting TO analyst;

EXECUTE AS USER = N'amy_analyst';

SELECT TOP (3) BranchName, Loans, Outstanding
FROM reporting.vBranchBook
ORDER BY Outstanding DESC;

REVERT;
GO

-- The database: CREATE TABLE needs CREATE TABLE and ALTER on the schema
CREATE SCHEMA sandbox AUTHORIZATION dbo;
GO
-- Deliberate error 262: no CREATE TABLE permission
EXECUTE AS USER = N'amy_analyst';
CREATE TABLE sandbox.AnalystScratch (ID INT NOT NULL);
REVERT;
GO
IF USER_NAME() <> N'dbo' REVERT;
GO
GRANT CREATE TABLE TO risk_manager;
GO
-- Deliberate error 2760: no ALTER on the schema sandbox
EXECUTE AS USER = N'cara_risk';
CREATE TABLE sandbox.StressTest (LoanID INT NOT NULL);
REVERT;
GO
IF USER_NAME() <> N'dbo' REVERT;
GO
GRANT ALTER ON SCHEMA::sandbox TO risk_manager;

EXECUTE AS USER = N'cara_risk';
CREATE TABLE sandbox.StressTest (
    LoanID    INT          NOT NULL,
    ShockedPD DECIMAL(6,4) NULL
);
REVERT;
GO
-- SHOWPLAN and VIEW DEFINITION
GRANT SHOWPLAN TO risk_manager;
GRANT VIEW DEFINITION TO auditor;

EXECUTE AS USER = N'dan_auditor';
SELECT HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'VIEW DEFINITION')
           AS ViewDefinition,
       HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'SHOWPLAN')
           AS Showplan;
REVERT;
GO

-- The server: server permissions are granted from master
USE master;
GO

-- Example password for a practice server: real passwords never go in scripts
CREATE LOGIN nb_dba_support WITH PASSWORD = N'Gx5#Copper2026!';

GRANT VIEW SERVER STATE TO nb_dba_support;
GRANT ALTER ANY LOGIN   TO nb_dba_support;

EXECUTE AS LOGIN = N'nb_dba_support';
SELECT HAS_PERMS_BY_NAME(NULL, NULL, N'VIEW SERVER STATE')
           AS ViewServerState,
       HAS_PERMS_BY_NAME(NULL, NULL, N'ALTER ANY LOGIN')
           AS AlterAnyLogin,
       HAS_PERMS_BY_NAME(NULL, NULL, N'CONTROL SERVER')
           AS ControlServer;
REVERT;
GO
-- The login's server permissions: these two, and CONNECT SQL
SELECT permission_name, state_desc
FROM sys.server_permissions
WHERE grantee_principal_id = SUSER_ID(N'nb_dba_support')
ORDER BY permission_name;
GO

USE NorthbridgeLending;
GO


-- ==============================================================
-- 3. DENY, and which permission wins
-- ==============================================================

GRANT SELECT ON SCHEMA::dbo TO auditor;
DENY SELECT ON dbo.Customer TO auditor;
DENY SELECT ON dbo.CreditRating TO auditor;
GO
-- Contains deliberate error 229: the object DENY wins over the schema GRANT
EXECUTE AS USER = N'dan_auditor';

SELECT COUNT(*) AS Loans
FROM dbo.Loan;

SELECT COUNT(*) AS Customers
FROM dbo.Customer;                 -- error 229

REVERT;
GO
IF USER_NAME() <> N'dbo' REVERT;
GO
-- The column exception: a column GRANT wins over a table DENY
GRANT SELECT ON dbo.Customer (CustomerID, City) TO auditor;

EXECUTE AS USER = N'dan_auditor';

SELECT TOP (3) City, COUNT(CustomerID) AS Customers
FROM dbo.Customer
GROUP BY City
ORDER BY Customers DESC, City;

REVERT;
GO


-- ==============================================================
-- 4. REVOKE, WITH GRANT OPTION, AS and CASCADE
-- ==============================================================

REVOKE SELECT ON dbo.CreditRating FROM auditor;    -- removes the DENY

EXECUTE AS USER = N'dan_auditor';
SELECT HAS_PERMS_BY_NAME(N'dbo.CreditRating', N'OBJECT', N'SELECT')
           AS ReadRatings;
REVERT;
GO
-- WITH GRANT OPTION
GRANT SELECT ON dbo.Product TO cara_risk WITH GRANT OPTION;

EXECUTE AS USER = N'cara_risk';
GRANT SELECT ON dbo.Product TO ben_collections;   -- cara passes it on
REVERT;
GO
SELECT USER_NAME(pe.grantee_principal_id) AS Grantee,
       USER_NAME(pe.grantor_principal_id) AS Grantor,
       pe.permission_name,
       pe.state_desc
FROM sys.database_permissions AS pe
WHERE pe.class = 1                         -- objects and columns
  AND pe.major_id = OBJECT_ID(N'dbo.Product')
ORDER BY Grantee;
GO
-- Deliberate error 4611: a grantable permission needs CASCADE
REVOKE SELECT ON dbo.Product FROM cara_risk;
GO
-- Remove only the right to share, and what was shared
REVOKE GRANT OPTION FOR SELECT ON dbo.Product
    FROM cara_risk CASCADE;
GO
SELECT USER_NAME(pe.grantee_principal_id) AS Grantee,
       USER_NAME(pe.grantor_principal_id) AS Grantor,
       pe.permission_name,
       pe.state_desc
FROM sys.database_permissions AS pe
WHERE pe.class = 1
  AND pe.major_id = OBJECT_ID(N'dbo.Product')
ORDER BY Grantee;
GO
-- A plain REVOKE now works
REVOKE SELECT ON dbo.Product FROM cara_risk;
GO
-- AS: the role risk_manager is recorded as grantor
GRANT SELECT ON dbo.Collateral TO risk_manager WITH GRANT OPTION;

GRANT SELECT ON dbo.Collateral TO collections_officer AS risk_manager;
GO
SELECT USER_NAME(pe.grantee_principal_id) AS Grantee,
       USER_NAME(pe.grantor_principal_id) AS Grantor,
       pe.state_desc
FROM sys.database_permissions AS pe
WHERE pe.class = 1
  AND pe.major_id = OBJECT_ID(N'dbo.Collateral')
ORDER BY Grantee;
GO


-- ==============================================================
-- 5. Ownership chaining and EXECUTE AS in a module
-- ==============================================================

CREATE OR ALTER PROCEDURE dbo.usp_ArrearsByBranch
AS
BEGIN
    SET NOCOUNT ON;
    SELECT b.BranchName,
           COUNT(*)                  AS ArrearsLoans,
           SUM(l.OutstandingBalance) AS ArrearsBalance
    FROM dbo.Loan AS l
    INNER JOIN dbo.Branch AS b
        ON b.BranchID = l.BranchID
    WHERE l.LoanStatus = N'Arrears'
    GROUP BY b.BranchName
    ORDER BY ArrearsBalance DESC;
END;
GO

GRANT EXECUTE ON dbo.usp_ArrearsByBranch TO collections_officer;

EXECUTE AS USER = N'ben_collections';

EXEC dbo.usp_ArrearsByBranch;

SELECT HAS_PERMS_BY_NAME(N'dbo.Loan', N'OBJECT', N'SELECT')
           AS ReadLoan;

REVERT;
GO
-- Dynamic SQL breaks the chain
CREATE OR ALTER PROCEDURE dbo.usp_LoansByStatus
    @Status NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(200) =
        N'SELECT COUNT(*) AS Loans FROM dbo.Loan '
      + N'WHERE LoanStatus = @s;';
    EXEC sys.sp_executesql @sql, N'@s NVARCHAR(20)', @s = @Status;
END;
GO

GRANT EXECUTE ON dbo.usp_LoansByStatus TO collections_officer;
GO
-- Deliberate error 229: the dynamic SELECT is checked with ben's permissions
EXECUTE AS USER = N'ben_collections';
EXEC dbo.usp_LoansByStatus @Status = N'Default';   -- error 229
REVERT;
GO
IF USER_NAME() <> N'dbo' REVERT;
GO
-- EXECUTE AS OWNER: the body runs as dbo
CREATE OR ALTER PROCEDURE dbo.usp_LoansByStatus
    @Status NVARCHAR(20)
WITH EXECUTE AS OWNER                  -- the body runs as dbo
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(200) =
        N'SELECT COUNT(*) AS Loans FROM dbo.Loan '
      + N'WHERE LoanStatus = @s;';
    EXEC sys.sp_executesql @sql, N'@s NVARCHAR(20)', @s = @Status;
END;
GO

EXECUTE AS USER = N'ben_collections';
EXEC dbo.usp_LoansByStatus @Status = N'Default';
REVERT;
GO


-- ==============================================================
-- 6. Checking permissions
-- ==============================================================

EXECUTE AS USER = N'ben_collections';

SELECT subentity_name AS ColumnName, permission_name
FROM fn_my_permissions(N'dbo.Customer', N'OBJECT')
WHERE subentity_name <> N''
ORDER BY ColumnName, permission_name;

REVERT;
GO
-- Everything recorded for the role collections_officer
SELECT CASE pe.class
           WHEN 0 THEN DB_NAME()
           WHEN 3 THEN SCHEMA_NAME(pe.major_id)
           ELSE OBJECT_NAME(pe.major_id)
       END                                AS Securable,
       COL_NAME(pe.major_id, pe.minor_id) AS ColumnName,
       pe.permission_name,
       pe.state_desc,
       USER_NAME(pe.grantor_principal_id) AS Grantor
FROM sys.database_permissions AS pe
WHERE pe.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'collections_officer')
ORDER BY Securable, ColumnName, pe.permission_name;
GO


-- ==============================================================
-- 7. Dynamic data masking
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_Customer;

SELECT CustomerID, FirstName, LastName, Email, Phone,
       DateOfBirth, AnnualIncome, City
INTO dbo.Practice_Customer
FROM dbo.Customer;
GO
ALTER TABLE dbo.Practice_Customer
    ALTER COLUMN Email ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE dbo.Practice_Customer
    ALTER COLUMN Phone
    ADD MASKED WITH (FUNCTION = 'partial(0,"XXXXXXXXX",3)');
ALTER TABLE dbo.Practice_Customer
    ALTER COLUMN DateOfBirth ADD MASKED WITH (FUNCTION = 'default()');
ALTER TABLE dbo.Practice_Customer
    ALTER COLUMN AnnualIncome ADD MASKED WITH (FUNCTION = 'default()');
GO
GRANT SELECT ON dbo.Practice_Customer TO collections_officer;

EXECUTE AS USER = N'ben_collections';

SELECT CustomerID, Email, Phone, DateOfBirth, AnnualIncome
FROM dbo.Practice_Customer
WHERE CustomerID IN (1, 3)
ORDER BY CustomerID;

REVERT;
GO
-- UNMASK on one column (SQL Server 2022 and later)
GRANT UNMASK ON dbo.Practice_Customer (Phone) TO collections_officer;

EXECUTE AS USER = N'ben_collections';

SELECT CustomerID, Email, Phone
FROM dbo.Practice_Customer
WHERE CustomerID IN (1, 3)
ORDER BY CustomerID;

REVERT;
GO
-- The masked columns of the table
SELECT name AS ColumnName
FROM sys.masked_columns
WHERE object_id = OBJECT_ID(N'dbo.Practice_Customer')
ORDER BY name;
GO


-- ==============================================================
-- 8. Row-level security
-- ==============================================================

CREATE SCHEMA security AUTHORIZATION dbo;
GO

DROP TABLE IF EXISTS dbo.Practice_Loan;

SELECT *
INTO dbo.Practice_Loan
FROM dbo.Loan;

ALTER TABLE dbo.Practice_Loan
    ADD CONSTRAINT PK_Practice_Loan PRIMARY KEY (LoanID);

CREATE TABLE dbo.Practice_UserBranch (
    UserName SYSNAME NOT NULL
             CONSTRAINT PK_Practice_UserBranch PRIMARY KEY,
    BranchID INT     NOT NULL
);
GO
INSERT INTO dbo.Practice_UserBranch (UserName, BranchID)
VALUES (N'officer_leeds', 4),
       (N'officer_bristol', 5);

CREATE USER officer_leeds   WITHOUT LOGIN;
CREATE USER officer_bristol WITHOUT LOGIN;
CREATE ROLE loan_officer AUTHORIZATION dbo;
GO
ALTER ROLE loan_officer ADD MEMBER officer_leeds;
ALTER ROLE loan_officer ADD MEMBER officer_bristol;

GRANT SELECT, INSERT, UPDATE ON dbo.Practice_Loan TO loan_officer;
GRANT SELECT ON dbo.Practice_Loan TO risk_manager;
GO

CREATE FUNCTION security.fn_LoanBranchFilter (@BranchID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS AllowRow
    WHERE USER_NAME() = N'dbo'                   -- administrators
       OR IS_ROLEMEMBER(N'risk_manager') = 1     -- risk: all rows
       OR EXISTS (SELECT 1
                  FROM dbo.Practice_UserBranch AS ub
                  WHERE ub.UserName = USER_NAME()
                    AND ub.BranchID = @BranchID); -- own branch
GO

CREATE SECURITY POLICY security.LoanBranchPolicy
    ADD FILTER PREDICATE security.fn_LoanBranchFilter(BranchID)
        ON dbo.Practice_Loan
    WITH (STATE = ON);
GO
-- The same query, three users
EXECUTE AS USER = N'officer_leeds';
SELECT COUNT(*) AS Loans, SUM(OutstandingBalance) AS Balance
FROM dbo.Practice_Loan;
REVERT;

EXECUTE AS USER = N'officer_bristol';
SELECT COUNT(*) AS Loans, SUM(OutstandingBalance) AS Balance
FROM dbo.Practice_Loan;
REVERT;

EXECUTE AS USER = N'cara_risk';
SELECT COUNT(*) AS Loans
FROM dbo.Practice_Loan;
REVERT;
GO
-- Block predicates
ALTER SECURITY POLICY security.LoanBranchPolicy
    ADD BLOCK PREDICATE security.fn_LoanBranchFilter(BranchID)
        ON dbo.Practice_Loan AFTER INSERT,
    ADD BLOCK PREDICATE security.fn_LoanBranchFilter(BranchID)
        ON dbo.Practice_Loan AFTER UPDATE;
GO
EXECUTE AS USER = N'officer_leeds';
UPDATE dbo.Practice_Loan
SET InterestRate = 8.50
WHERE LoanID = 10007;                 -- a Leeds loan: allowed
REVERT;

EXECUTE AS USER = N'officer_bristol';
UPDATE dbo.Practice_Loan
SET InterestRate = 8.50
WHERE LoanID = 10007;                 -- invisible to Bristol: 0 rows
REVERT;
GO
-- Deliberate error 33504: the block predicate refuses the move
EXECUTE AS USER = N'officer_leeds';
UPDATE dbo.Practice_Loan
SET BranchID = 5                      -- move it to Bristol
WHERE LoanID = 10007;
REVERT;
GO
IF USER_NAME() <> N'dbo' REVERT;
GO
-- The policy and its predicates
SELECT name, is_enabled
FROM sys.security_policies;

SELECT predicate_type_desc, operation_desc
FROM sys.security_predicates
ORDER BY predicate_type_desc, operation_desc;
GO


-- ==============================================================
-- Applied example: least privilege for the four teams
-- ==============================================================

-- Step 2. Complete the grants of the Course
GRANT SELECT ON dbo.Loan
    (LoanID, CustomerID, BranchID, LoanStatus,
     MonthlyPayment, OutstandingBalance)
    TO collections_officer;
GRANT SELECT, INSERT ON dbo.Payment TO collections_officer;

GRANT SELECT ON SCHEMA::dbo TO risk_manager;

DENY INSERT, UPDATE, DELETE ON SCHEMA::dbo TO auditor;
GO
-- Step 3. Recorded permissions per role
SELECT pr.name AS TeamRole,
       SUM(CASE WHEN pe.state_desc LIKE N'GRANT%' THEN 1 ELSE 0 END)
           AS Grants,
       SUM(CASE WHEN pe.state_desc = N'DENY' THEN 1 ELSE 0 END)
           AS Denies
FROM sys.database_permissions AS pe
INNER JOIN sys.database_principals AS pr
    ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name IN (N'analyst', N'collections_officer',
                  N'risk_manager', N'auditor')
GROUP BY pr.name
ORDER BY pr.name;
GO
-- Step 4. Test each team
EXECUTE AS USER = N'amy_analyst';
SELECT N'analyst' AS Team,
    HAS_PERMS_BY_NAME(N'dbo.Loan', N'OBJECT', N'SELECT') AS ReadLoan,
    HAS_PERMS_BY_NAME(N'dbo.Customer', N'OBJECT', N'SELECT',
                      N'City', N'COLUMN')  AS ReadCity,
    HAS_PERMS_BY_NAME(N'dbo.Customer', N'OBJECT', N'SELECT',
                      N'Email', N'COLUMN') AS ReadEmail,
    HAS_PERMS_BY_NAME(N'dbo.Loan', N'OBJECT', N'UPDATE')
                                           AS UpdateLoan,
    HAS_PERMS_BY_NAME(N'dbo.usp_ArrearsByBranch', N'OBJECT',
                      N'EXECUTE')          AS RunArrears;
REVERT;
GO
EXECUTE AS USER = N'ben_collections';
SELECT N'collections_officer' AS Team,
    HAS_PERMS_BY_NAME(N'dbo.Loan', N'OBJECT', N'SELECT') AS ReadLoan,
    HAS_PERMS_BY_NAME(N'dbo.Customer', N'OBJECT', N'SELECT',
                      N'City', N'COLUMN')  AS ReadCity,
    HAS_PERMS_BY_NAME(N'dbo.Customer', N'OBJECT', N'SELECT',
                      N'Email', N'COLUMN') AS ReadEmail,
    HAS_PERMS_BY_NAME(N'dbo.Loan', N'OBJECT', N'UPDATE')
                                           AS UpdateLoan,
    HAS_PERMS_BY_NAME(N'dbo.usp_ArrearsByBranch', N'OBJECT',
                      N'EXECUTE')          AS RunArrears;
REVERT;
GO
EXECUTE AS USER = N'cara_risk';
SELECT N'risk_manager' AS Team,
    HAS_PERMS_BY_NAME(N'dbo.Loan', N'OBJECT', N'SELECT') AS ReadLoan,
    HAS_PERMS_BY_NAME(N'dbo.Customer', N'OBJECT', N'SELECT',
                      N'City', N'COLUMN')  AS ReadCity,
    HAS_PERMS_BY_NAME(N'dbo.Customer', N'OBJECT', N'SELECT',
                      N'Email', N'COLUMN') AS ReadEmail,
    HAS_PERMS_BY_NAME(N'dbo.Loan', N'OBJECT', N'UPDATE')
                                           AS UpdateLoan,
    HAS_PERMS_BY_NAME(N'dbo.usp_ArrearsByBranch', N'OBJECT',
                      N'EXECUTE')          AS RunArrears;
REVERT;
GO
EXECUTE AS USER = N'dan_auditor';
SELECT N'auditor' AS Team,
    HAS_PERMS_BY_NAME(N'dbo.Loan', N'OBJECT', N'SELECT') AS ReadLoan,
    HAS_PERMS_BY_NAME(N'dbo.Customer', N'OBJECT', N'SELECT',
                      N'City', N'COLUMN')  AS ReadCity,
    HAS_PERMS_BY_NAME(N'dbo.Customer', N'OBJECT', N'SELECT',
                      N'Email', N'COLUMN') AS ReadEmail,
    HAS_PERMS_BY_NAME(N'dbo.Loan', N'OBJECT', N'UPDATE')
                                           AS UpdateLoan,
    HAS_PERMS_BY_NAME(N'dbo.usp_ArrearsByBranch', N'OBJECT',
                      N'EXECUTE')          AS RunArrears;
REVERT;
GO


-- ==============================================================
-- Step 5. Clean-up: every object, user, role and the login
-- ==============================================================

DROP SECURITY POLICY IF EXISTS security.LoanBranchPolicy;
GO
DROP FUNCTION IF EXISTS security.fn_LoanBranchFilter;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS dbo.Practice_UserBranch;
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS sandbox.StressTest;
DROP TABLE IF EXISTS sandbox.AnalystScratch;
DROP VIEW IF EXISTS reporting.vBranchBook;
DROP PROCEDURE IF EXISTS dbo.usp_ArrearsByBranch;
DROP PROCEDURE IF EXISTS dbo.usp_LoansByStatus;
GO
DROP SCHEMA IF EXISTS reporting;
DROP SCHEMA IF EXISTS sandbox;
DROP SCHEMA IF EXISTS security;
GO
DROP USER IF EXISTS ben_collections;
DROP USER IF EXISTS amy_analyst;
DROP USER IF EXISTS dan_auditor;
DROP USER IF EXISTS cara_risk;
DROP USER IF EXISTS officer_leeds;
DROP USER IF EXISTS officer_bristol;
GO
DROP ROLE IF EXISTS collections_officer;
DROP ROLE IF EXISTS analyst;
DROP ROLE IF EXISTS auditor;
DROP ROLE IF EXISTS loan_officer;
DROP ROLE IF EXISTS risk_manager;
GO
-- Server-level: the login and its server permissions
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'nb_dba_support')
    DROP LOGIN nb_dba_support;
GO
