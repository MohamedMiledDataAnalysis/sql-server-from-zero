/* SQL Server from Zero — Volume 1
   Chapter 25: User-defined types and table types — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

/* The exercises create user-defined types and practice tables.
   No base table is changed. The clean-up block at the end removes
   the objects the exercises create; dbo.Money2 and dbo.LoanIdList
   are Course types and stay in place (the Course script removes them). */

-- Start from a clean state so that the script can run more than once
DROP TABLE IF EXISTS dbo.Practice_VehicleCollateral;
DROP TABLE IF EXISTS #Valuation;
DROP TYPE IF EXISTS dbo.CreditScoreValue;
DROP TYPE IF EXISTS dbo.EmailAddress;
DROP TYPE IF EXISTS dbo.CustomerIdList;
DROP TYPE IF EXISTS dbo.Money4;
DROP TYPE IF EXISTS dbo.PaymentBatch;
GO

-- Types from the Course that the exercises use: create them if missing
IF TYPE_ID(N'dbo.Money2') IS NULL
    EXEC (N'CREATE TYPE dbo.Money2 FROM DECIMAL(12,2) NOT NULL;');
IF TYPE_ID(N'dbo.LoanIdList') IS NULL
    EXEC (N'CREATE TYPE dbo.LoanIdList AS TABLE
            (LoanID INT NOT NULL PRIMARY KEY);');
GO

-- ------------------------------------------------------------
-- Correction 25.1
-- ------------------------------------------------------------

CREATE TYPE dbo.CreditScoreValue
    FROM SMALLINT NOT NULL;     -- CreditScore is SMALLINT
GO

DECLARE @Score dbo.CreditScoreValue,
        @LastName NVARCHAR(40);

SELECT @Score = CreditScore,    -- one row: CustomerID is the key
       @LastName = LastName
FROM dbo.Customer
WHERE CustomerID = 208;

SELECT @LastName AS LastName, @Score AS CreditScore;
GO

-- ------------------------------------------------------------
-- Correction 25.2
-- ------------------------------------------------------------

CREATE TYPE dbo.EmailAddress
    FROM NVARCHAR(100) NULL;     -- columns accept NULL by default
GO

SELECT
    name,
    TYPE_NAME(system_type_id) AS BaseType,
    max_length,                  -- bytes, not characters
    is_nullable
FROM sys.types
WHERE name = N'EmailAddress'
  AND is_user_defined = 1;
GO

-- ------------------------------------------------------------
-- Correction 25.3
-- ------------------------------------------------------------

CREATE TYPE dbo.CustomerIdList AS TABLE
(
    CustomerID INT NOT NULL PRIMARY KEY
);
GO

DECLARE @Customers dbo.CustomerIdList;

INSERT INTO @Customers (CustomerID)
VALUES (11), (208), (285);

SELECT c.CustomerID, c.FirstName, c.LastName, c.CreditScore
FROM dbo.Customer AS c
INNER JOIN @Customers AS x        -- the variable is a table
    ON x.CustomerID = c.CustomerID
ORDER BY c.CustomerID;
GO

-- ------------------------------------------------------------
-- Correction 25.4
-- ------------------------------------------------------------

DROP TABLE IF EXISTS dbo.Practice_VehicleCollateral;

CREATE TABLE dbo.Practice_VehicleCollateral
(
    CollateralID    INT NOT NULL PRIMARY KEY,
    LoanID          INT NOT NULL,
    ValuationAmount dbo.Money2         -- DECIMAL(12,2) NOT NULL
);

INSERT INTO dbo.Practice_VehicleCollateral
    (CollateralID, LoanID, ValuationAmount)
SELECT CollateralID, LoanID, ValuationAmount
FROM dbo.Collateral
WHERE CollateralType = N'Vehicle';

SELECT COUNT(*) AS Vehicles,
       SUM(ValuationAmount) AS TotalValuation
FROM dbo.Practice_VehicleCollateral;
GO

-- ------------------------------------------------------------
-- Correction 25.5
-- ------------------------------------------------------------

DECLARE @Ids dbo.LoanIdList;

INSERT INTO @Ids (LoanID)
SELECT TOP (10) LoanID
FROM dbo.Loan
WHERE BranchID = 8
ORDER BY Principal DESC, LoanID;   -- LoanID breaks ties

EXEC sp_executesql
    N'SELECT COUNT(*) AS Loans,
             SUM(l.OutstandingBalance) AS TotalOutstanding
      FROM dbo.Loan AS l
      INNER JOIN @LoanIds AS i
          ON i.LoanID = l.LoanID;',
    N'@LoanIds dbo.LoanIdList READONLY',   -- READONLY is required
    @LoanIds = @Ids;
GO

-- ------------------------------------------------------------
-- Correction 25.6
-- ------------------------------------------------------------

-- FAILS ON PURPOSE: Msg 3732
-- 1. Refused: the table uses the type
-- DROP TYPE dbo.Money2;
GO

-- 2. The working order: table first, type second
DROP TABLE IF EXISTS dbo.Practice_VehicleCollateral;
DROP TYPE IF EXISTS dbo.Money2;
GO

SELECT COUNT(*) AS Money2Types
FROM sys.types
WHERE name = N'Money2'
  AND is_user_defined = 1;
GO

-- 3. Recreate the type for the next exercises
CREATE TYPE dbo.Money2
    FROM DECIMAL(12,2) NOT NULL;
GO

-- ------------------------------------------------------------
-- Correction 25.7
-- ------------------------------------------------------------

DROP TABLE IF EXISTS dbo.Practice_VehicleCollateral;

CREATE TABLE dbo.Practice_VehicleCollateral
(
    CollateralID    INT NOT NULL PRIMARY KEY,
    LoanID          INT NOT NULL,
    ValuationAmount dbo.Money2
);

INSERT INTO dbo.Practice_VehicleCollateral
    (CollateralID, LoanID, ValuationAmount)
SELECT CollateralID, LoanID, ValuationAmount
FROM dbo.Collateral
WHERE CollateralType = N'Vehicle';
GO

CREATE TYPE dbo.Money4
    FROM DECIMAL(16,4) NOT NULL;   -- 12 digits before the point
GO

ALTER TABLE dbo.Practice_VehicleCollateral
    ALTER COLUMN ValuationAmount dbo.Money4 NOT NULL;
GO

SELECT TYPE_NAME(user_type_id) AS DeclaredType,
       [precision],
       scale
FROM sys.columns
WHERE object_id = OBJECT_ID(N'dbo.Practice_VehicleCollateral')
  AND name = N'ValuationAmount';

SELECT SUM(ValuationAmount) AS TotalValuation
FROM dbo.Practice_VehicleCollateral;
GO

-- ------------------------------------------------------------
-- Correction 25.8
-- ------------------------------------------------------------

CREATE TYPE dbo.PaymentBatch AS TABLE
(
    PaymentID  INT           NOT NULL PRIMARY KEY,
    AmountPaid DECIMAL(12,2) NOT NULL CHECK (AmountPaid > 0),
    PaidDate   DATE          NOT NULL DEFAULT ('2026-09-30')
);
GO

DECLARE @Batch dbo.PaymentBatch;

INSERT INTO @Batch (PaymentID, AmountPaid)  -- PaidDate left out
VALUES (82, 239.08),
       (83, 239.08);

SELECT PaymentID, AmountPaid, PaidDate
FROM @Batch
ORDER BY PaymentID;

-- FAILS ON PURPOSE: Msg 547, CHECK constraint
-- INSERT INTO @Batch (PaymentID, AmountPaid)
-- VALUES (84, 0.00);                          -- breaks the CHECK
GO

-- ============================================================
-- Clean-up: remove every object this script created
-- ============================================================

DROP TABLE IF EXISTS dbo.Practice_VehicleCollateral;
DROP TABLE IF EXISTS #Valuation;
DROP TYPE IF EXISTS dbo.CreditScoreValue;
DROP TYPE IF EXISTS dbo.EmailAddress;
DROP TYPE IF EXISTS dbo.CustomerIdList;
DROP TYPE IF EXISTS dbo.Money4;
DROP TYPE IF EXISTS dbo.PaymentBatch;
GO
