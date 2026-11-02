/* SQL Server from Zero — Volume 2
   Chapter 30: GRANT, DENY and REVOKE — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022);
   UNMASK on a table needs SQL Server 2022 or later.
   Creates no server-level object. */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Start-up clean-up: lets the script run again after an interruption
-- ==============================================================

DROP SECURITY POLICY IF EXISTS security.CustomerBranchPolicy;
GO
DROP FUNCTION IF EXISTS security.fn_CustomerBranchFilter;
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
DROP PROCEDURE IF EXISTS dbo.usp_BranchOfficers;
GO
DROP SCHEMA IF EXISTS security;
GO
DROP USER IF EXISTS gus_temp;          -- grantee before grantor
DROP USER IF EXISTS fay_hr;
DROP USER IF EXISTS eve_branch;
DROP USER IF EXISTS officer_leeds;
DROP USER IF EXISTS officer_bristol;
DROP ROLE IF EXISTS branch_admin;
GO


-- ==============================================================
-- Exercise setup (run once before 30.1)
-- ==============================================================

CREATE ROLE branch_admin AUTHORIZATION dbo;
CREATE USER eve_branch WITHOUT LOGIN;
CREATE USER fay_hr     WITHOUT LOGIN;
CREATE USER gus_temp   WITHOUT LOGIN;
GO
ALTER ROLE branch_admin ADD MEMBER eve_branch;
GO


-- ==============================================================
-- Correction 30.1
-- ==============================================================

GRANT SELECT ON dbo.Branch      TO branch_admin;
GRANT SELECT ON dbo.LoanOfficer TO branch_admin;

EXECUTE AS USER = N'eve_branch';

SELECT COUNT(*) AS Officers
FROM dbo.LoanOfficer;

SELECT HAS_PERMS_BY_NAME(N'dbo.LoanOfficer', N'OBJECT', N'SELECT')
           AS ReadOfficer,
       HAS_PERMS_BY_NAME(N'dbo.Branch', N'OBJECT', N'SELECT')
           AS ReadBranch,
       HAS_PERMS_BY_NAME(N'dbo.Branch', N'OBJECT', N'UPDATE')
           AS UpdateBranch;

REVERT;
GO


-- ==============================================================
-- Correction 30.2
-- ==============================================================

GRANT SELECT ON dbo.Payment (LoanID, DueDate, AmountDue, PaidDate)
    TO branch_admin;

EXECUTE AS USER = N'eve_branch';

SELECT COUNT(LoanID)  AS MissedInstalments,
       SUM(AmountDue) AS AmountMissed
FROM dbo.Payment
WHERE PaidDate IS NULL                     -- missed
  AND DueDate >= '2026-09-01'
  AND DueDate <  '2026-10-01';             -- September 2026

REVERT;
GO


-- ==============================================================
-- Correction 30.3
-- ==============================================================

SELECT OBJECT_NAME(pe.major_id)           AS Securable,
       COL_NAME(pe.major_id, pe.minor_id) AS ColumnName,
       pe.permission_name,
       pe.state_desc
FROM sys.database_permissions AS pe
WHERE pe.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'branch_admin')
ORDER BY Securable, ColumnName;
GO


-- ==============================================================
-- Correction 30.4
-- ==============================================================

GRANT SELECT ON SCHEMA::dbo TO branch_admin;
DENY SELECT ON dbo.CreditRating TO branch_admin;

EXECUTE AS USER = N'eve_branch';
SELECT HAS_PERMS_BY_NAME(N'dbo.Loan', N'OBJECT', N'SELECT')
           AS ReadLoan,
       HAS_PERMS_BY_NAME(N'dbo.CreditRating', N'OBJECT', N'SELECT')
           AS ReadRatings;
REVERT;

REVOKE SELECT ON dbo.CreditRating FROM branch_admin;  -- DENY removed

EXECUTE AS USER = N'eve_branch';
SELECT HAS_PERMS_BY_NAME(N'dbo.CreditRating', N'OBJECT', N'SELECT')
           AS ReadRatings;
REVERT;
GO


-- ==============================================================
-- Correction 30.5
-- ==============================================================

CREATE OR ALTER PROCEDURE dbo.usp_BranchOfficers
    @BranchID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT OfficerID, FirstName, LastName
    FROM dbo.LoanOfficer
    WHERE BranchID = @BranchID
    ORDER BY OfficerID;
END;
GO

GRANT EXECUTE ON dbo.usp_BranchOfficers TO fay_hr;

EXECUTE AS USER = N'fay_hr';

EXEC dbo.usp_BranchOfficers @BranchID = 4;

SELECT HAS_PERMS_BY_NAME(N'dbo.LoanOfficer', N'OBJECT', N'SELECT')
           AS ReadOfficer;

REVERT;
GO


-- ==============================================================
-- Correction 30.6
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;

SELECT *
INTO dbo.Practice_LoanOfficer
FROM dbo.LoanOfficer;
GO
ALTER TABLE dbo.Practice_LoanOfficer
    ALTER COLUMN Email ADD MASKED WITH (FUNCTION = 'email()');

GRANT SELECT ON dbo.Practice_LoanOfficer TO fay_hr;

EXECUTE AS USER = N'fay_hr';
SELECT OfficerID, Email
FROM dbo.Practice_LoanOfficer
WHERE OfficerID BETWEEN 110 AND 112
ORDER BY OfficerID;
REVERT;
GO
GRANT UNMASK ON dbo.Practice_LoanOfficer TO fay_hr;   -- whole table

EXECUTE AS USER = N'fay_hr';
SELECT OfficerID, Email
FROM dbo.Practice_LoanOfficer
WHERE OfficerID BETWEEN 110 AND 112
ORDER BY OfficerID;
REVERT;
GO


-- ==============================================================
-- Correction 30.7
-- ==============================================================

IF SCHEMA_ID(N'security') IS NULL
    EXEC (N'CREATE SCHEMA security AUTHORIZATION dbo;');

DROP TABLE IF EXISTS dbo.Practice_Customer;

SELECT *
INTO dbo.Practice_Customer
FROM dbo.Customer;

CREATE USER officer_leeds   WITHOUT LOGIN;
CREATE USER officer_bristol WITHOUT LOGIN;
GO
GRANT SELECT, UPDATE ON dbo.Practice_Customer
    TO officer_leeds, officer_bristol;
GO

CREATE FUNCTION security.fn_CustomerBranchFilter (@HomeBranchID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS AllowRow
    WHERE USER_NAME() = N'dbo'
       OR (USER_NAME() = N'officer_leeds'   AND @HomeBranchID = 4)
       OR (USER_NAME() = N'officer_bristol' AND @HomeBranchID = 5);
GO

CREATE SECURITY POLICY security.CustomerBranchPolicy
    ADD FILTER PREDICATE
        security.fn_CustomerBranchFilter(HomeBranchID)
        ON dbo.Practice_Customer,
    ADD BLOCK PREDICATE
        security.fn_CustomerBranchFilter(HomeBranchID)
        ON dbo.Practice_Customer AFTER UPDATE
    WITH (STATE = ON);
GO

EXECUTE AS USER = N'officer_leeds';
SELECT COUNT(*) AS Customers FROM dbo.Practice_Customer;
REVERT;

EXECUTE AS USER = N'officer_bristol';
SELECT COUNT(*) AS Customers FROM dbo.Practice_Customer;
REVERT;
GO
-- dbo sees every customer
SELECT COUNT(*) AS Customers FROM dbo.Practice_Customer;
GO
-- Deliberate error 33504: the block predicate refuses the move
EXECUTE AS USER = N'officer_leeds';
UPDATE dbo.Practice_Customer
SET HomeBranchID = 5                   -- leaves Leeds: blocked
WHERE CustomerID = 9;
REVERT;
GO
-- Safety net for the automated run: never stay impersonated
IF USER_NAME() <> N'dbo' REVERT;
GO


-- ==============================================================
-- Correction 30.8
-- ==============================================================

GRANT EXECUTE ON dbo.usp_BranchOfficers TO eve_branch
    WITH GRANT OPTION;

EXECUTE AS USER = N'eve_branch';
GRANT EXECUTE ON dbo.usp_BranchOfficers TO gus_temp;
REVERT;
GO
SELECT USER_NAME(pe.grantee_principal_id) AS Grantee,
       USER_NAME(pe.grantor_principal_id) AS Grantor,
       pe.state_desc
FROM sys.database_permissions AS pe
WHERE pe.class = 1
  AND pe.major_id = OBJECT_ID(N'dbo.usp_BranchOfficers')
ORDER BY Grantee;
GO
REVOKE GRANT OPTION FOR EXECUTE ON dbo.usp_BranchOfficers
    FROM eve_branch CASCADE;          -- her sharing, and what she shared
GO
SELECT USER_NAME(pe.grantee_principal_id) AS Grantee,
       USER_NAME(pe.grantor_principal_id) AS Grantor,
       pe.state_desc
FROM sys.database_permissions AS pe
WHERE pe.class = 1
  AND pe.major_id = OBJECT_ID(N'dbo.usp_BranchOfficers')
ORDER BY Grantee;
GO


-- ==============================================================
-- Clean-up: remove every object created by the exercises
-- ==============================================================

DROP SECURITY POLICY IF EXISTS security.CustomerBranchPolicy;
GO
DROP FUNCTION IF EXISTS security.fn_CustomerBranchFilter;
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
DROP PROCEDURE IF EXISTS dbo.usp_BranchOfficers;
GO
DROP SCHEMA IF EXISTS security;
GO
DROP USER IF EXISTS gus_temp;
DROP USER IF EXISTS fay_hr;
DROP USER IF EXISTS eve_branch;
DROP USER IF EXISTS officer_leeds;
DROP USER IF EXISTS officer_bristol;
DROP ROLE IF EXISTS branch_admin;
GO
