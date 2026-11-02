/* SQL Server from Zero — Volume 1
   Chapter 25: User-defined types and table types
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

/* This script creates user-defined types and practice tables.
   It changes no base table. Tables are dropped before types, because
   a type in use cannot be dropped. Statements marked "FAILS ON PURPOSE"
   show an error message from the book; they are commented out so
   that the script runs end to end. Uncomment one to see its error. */

-- Start from a clean state so that the script can run more than once
DROP TABLE IF EXISTS
    dbo.Practice_RateReview,
    dbo.Practice_LoanRates;
DROP TABLE IF EXISTS #Stage;
DROP TYPE IF EXISTS dbo.Money2;
DROP TYPE IF EXISTS dbo.Money2_v2;
DROP TYPE IF EXISTS dbo.InterestRatePct;
DROP TYPE IF EXISTS dbo.LoanStatusName;
DROP TYPE IF EXISTS dbo.LoanIdList;
DROP TYPE IF EXISTS dbo.RateChangeBatch;
GO

-- ============================================================
-- 1. Alias types: a name for a type you use often
-- ============================================================

CREATE TYPE dbo.Money2
    FROM DECIMAL(12,2) NOT NULL;

CREATE TYPE dbo.InterestRatePct
    FROM DECIMAL(5,2) NOT NULL;

CREATE TYPE dbo.LoanStatusName
    FROM NVARCHAR(20) NOT NULL;
GO

DECLARE @Instalment dbo.Money2 = 1250.555;

SELECT @Instalment AS Instalment;
GO

DECLARE @Unknown dbo.Money2;

SELECT @Unknown AS NotYetSet;
GO

-- ============================================================
-- 2. Using alias types in tables
-- ============================================================

DROP TABLE IF EXISTS dbo.Practice_RateReview;

CREATE TABLE dbo.Practice_RateReview
(
    LoanID       INT                 NOT NULL
        CONSTRAINT PK_Practice_RateReview PRIMARY KEY,
    CurrentRate  dbo.InterestRatePct,          -- NOT NULL from type
    ProposedRate dbo.InterestRatePct NULL,     -- column overrides
    Balance      dbo.Money2,                   -- NOT NULL from type
    LoanStatus   dbo.LoanStatusName            -- NOT NULL from type
);
GO

INSERT INTO dbo.Practice_RateReview
    (LoanID, CurrentRate, Balance, LoanStatus)
SELECT LoanID, InterestRate, OutstandingBalance, LoanStatus
FROM dbo.Loan
WHERE LoanStatus = N'Arrears';

SELECT TOP (5) LoanID, CurrentRate, ProposedRate, Balance
FROM dbo.Practice_RateReview
ORDER BY LoanID;
GO

-- FAILS ON PURPOSE: Msg 515, NULL into a NOT NULL column
-- INSERT INTO dbo.Practice_RateReview
--     (LoanID, CurrentRate, Balance, LoanStatus)
-- VALUES
--     (99999, 5.00, NULL, N'Arrears');
GO

-- ============================================================
-- 3. Inspecting user-defined types
-- ============================================================

SELECT
    name,
    TYPE_NAME(system_type_id) AS BaseType,
    max_length,
    [precision],
    scale,
    is_nullable
FROM sys.types
WHERE is_user_defined = 1
  AND is_table_type = 0
ORDER BY name;
GO

SELECT
    OBJECT_SCHEMA_NAME(object_id) AS SchemaName,
    OBJECT_NAME(object_id) AS TableName,
    name AS ColumnName,
    TYPE_NAME(user_type_id) AS DeclaredType,
    is_nullable
FROM sys.columns
WHERE user_type_id IN (TYPE_ID(N'dbo.Money2'),
                       TYPE_ID(N'dbo.InterestRatePct'),
                       TYPE_ID(N'dbo.LoanStatusName'))
ORDER BY TableName, column_id;
GO

-- ============================================================
-- 4. Table types: a reusable table shape
-- ============================================================

CREATE TYPE dbo.LoanIdList AS TABLE
(
    LoanID INT NOT NULL PRIMARY KEY
);
GO

DECLARE @Ids dbo.LoanIdList;

INSERT INTO @Ids (LoanID)
VALUES (10001), (10002), (10003);

SELECT l.LoanID, l.LoanStatus, l.OutstandingBalance
FROM dbo.Loan AS l
INNER JOIN @Ids AS i
    ON i.LoanID = l.LoanID
ORDER BY l.LoanID;
GO

SELECT
    tt.name AS TableTypeName,
    c.name AS ColumnName,
    TYPE_NAME(c.user_type_id) AS ColumnType,
    c.is_nullable
FROM sys.table_types AS tt
INNER JOIN sys.columns AS c
    ON c.object_id = tt.type_table_object_id
WHERE tt.name = N'LoanIdList'
ORDER BY c.column_id;
GO

-- ============================================================
-- 5. Table-valued parameters with sp_executesql
-- ============================================================

DECLARE @Ids dbo.LoanIdList;

INSERT INTO @Ids (LoanID)
VALUES (10001), (10002), (10003);

EXEC sp_executesql
    N'SELECT l.LoanID, l.LoanStatus, l.OutstandingBalance
      FROM dbo.Loan AS l
      INNER JOIN @LoanIds AS i
          ON i.LoanID = l.LoanID
      ORDER BY l.LoanID;',
    N'@LoanIds dbo.LoanIdList READONLY',
    @LoanIds = @Ids;
GO

-- FAILS ON PURPOSE: Msg 352, READONLY missing
-- DECLARE @Ids dbo.LoanIdList;

-- EXEC sp_executesql
--     N'SELECT COUNT(*) FROM @LoanIds;',
--     N'@LoanIds dbo.LoanIdList',          -- READONLY missing
--     @LoanIds = @Ids;
GO

DECLARE @Ids dbo.LoanIdList,
        @Loans INT,
        @Total DECIMAL(14,2);

INSERT INTO @Ids (LoanID)
SELECT LoanID
FROM dbo.Loan
WHERE LoanStatus = N'Arrears';

EXEC sp_executesql
    N'SELECT @LoanCount = COUNT(*),
             @Outstanding = SUM(l.OutstandingBalance)
      FROM dbo.Loan AS l
      INNER JOIN @LoanIds AS i
          ON i.LoanID = l.LoanID;',
    N'@LoanIds dbo.LoanIdList READONLY,
      @LoanCount INT OUTPUT,
      @Outstanding DECIMAL(14,2) OUTPUT',
    @LoanIds = @Ids,
    @LoanCount = @Loans OUTPUT,
    @Outstanding = @Total OUTPUT;

SELECT @Loans AS LoansInList, @Total AS TotalOutstanding;
GO

-- ============================================================
-- 6. Dropping and replacing types
-- ============================================================

-- FAILS ON PURPOSE: Msg 3732, the type is in use
-- DROP TYPE dbo.Money2;
GO

CREATE TYPE dbo.Money2_v2
    FROM DECIMAL(14,2) NOT NULL;
GO

ALTER TABLE dbo.Practice_RateReview
    ALTER COLUMN Balance dbo.Money2_v2 NOT NULL;
GO

DROP TYPE dbo.Money2;
GO

SELECT name AS ColumnName,
       TYPE_NAME(user_type_id) AS DeclaredType,
       [precision],
       scale
FROM sys.columns
WHERE object_id = OBJECT_ID(N'dbo.Practice_RateReview')
  AND name = N'Balance';
GO

CREATE TYPE dbo.Money2
    FROM DECIMAL(12,2) NOT NULL;
GO

-- ============================================================
-- 7. When not to use alias types
-- ============================================================

-- FAILS ON PURPOSE: Msg 2715, tempdb does not know dbo.Money2
-- DROP TABLE IF EXISTS #Stage;

-- CREATE TABLE #Stage
-- (
--     LoanID INT NOT NULL,
--     Amount dbo.Money2
-- );
GO

DECLARE @Stage TABLE
(
    LoanID INT NOT NULL,
    Amount dbo.Money2
);

INSERT INTO @Stage (LoanID, Amount)
VALUES (10001, 1772.72);

SELECT LoanID, Amount FROM @Stage;
GO

-- ============================================================
-- Applied example
-- ============================================================

DROP TABLE IF EXISTS dbo.Practice_LoanRates;

SELECT LoanID, ProductCode, LoanStatus, InterestRate
INTO dbo.Practice_LoanRates
FROM dbo.Loan;
GO

DROP TYPE IF EXISTS dbo.RateChangeBatch;

CREATE TYPE dbo.RateChangeBatch AS TABLE
(
    LoanID  INT          NOT NULL PRIMARY KEY,
    NewRate DECIMAL(5,2) NOT NULL
        CHECK (NewRate >= 0.00 AND NewRate <= 25.00)
);
GO

-- FAILS ON PURPOSE: Msg 547, CHECK constraint of the table type
-- DECLARE @Batch dbo.RateChangeBatch;

-- INSERT INTO @Batch (LoanID, NewRate)
-- VALUES (10009, 30.00);     -- above 25.00: refused
GO

DECLARE @Batch dbo.RateChangeBatch;

INSERT INTO @Batch (LoanID, NewRate)
SELECT LoanID, InterestRate - 0.25   -- DECIMAL(5,2) minus 0.25
FROM dbo.Loan
WHERE ProductCode = 'MTG-TRK'
  AND LoanStatus = N'Active';

EXEC sp_executesql
    N'UPDATE r
      SET r.InterestRate = b.NewRate
      FROM dbo.Practice_LoanRates AS r
      INNER JOIN @RateBatch AS b
          ON b.LoanID = r.LoanID;',
    N'@RateBatch dbo.RateChangeBatch READONLY',
    @RateBatch = @Batch;
GO

SELECT TOP (5)
    r.LoanID,
    l.InterestRate AS OldRate,
    r.InterestRate AS NewRate,
    l.InterestRate - r.InterestRate AS Cut
FROM dbo.Practice_LoanRates AS r
INNER JOIN dbo.Loan AS l
    ON l.LoanID = r.LoanID
WHERE r.ProductCode = 'MTG-TRK'
ORDER BY r.LoanID;

SELECT COUNT(*) AS ChangedLoans
FROM dbo.Practice_LoanRates AS r
INNER JOIN dbo.Loan AS l
    ON l.LoanID = r.LoanID
WHERE r.InterestRate <> l.InterestRate;
GO

-- ============================================================
-- Clean-up: remove every object this script created
-- ============================================================

DROP TABLE IF EXISTS
    dbo.Practice_RateReview,
    dbo.Practice_LoanRates;
DROP TABLE IF EXISTS #Stage;
DROP TYPE IF EXISTS dbo.Money2;
DROP TYPE IF EXISTS dbo.Money2_v2;
DROP TYPE IF EXISTS dbo.InterestRatePct;
DROP TYPE IF EXISTS dbo.LoanStatusName;
DROP TYPE IF EXISTS dbo.LoanIdList;
DROP TYPE IF EXISTS dbo.RateChangeBatch;
GO
