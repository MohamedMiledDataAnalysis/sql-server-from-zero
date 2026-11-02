/* SQL Server from Zero — Volume 1
   Chapter 26: Stored procedures and functions — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

/* The exercises create procedures, functions and the practice table
   dbo.Practice_Loan26 (exercise 26.5 updates it; dbo.Loan is never
   changed). The clean-up block at the end removes the exercise objects. */

-- Start from a clean state so that the script can run more than once
DROP PROCEDURE IF EXISTS reporting.usp_ProductList;
DROP PROCEDURE IF EXISTS reporting.usp_TopCustomersInCity;
DROP PROCEDURE IF EXISTS reporting.usp_CustomerExposure;
DROP PROCEDURE IF EXISTS reporting.usp_SetPracticeStatus;
DROP PROCEDURE IF EXISTS reporting.usp_ExposureByProductType;
DROP PROCEDURE IF EXISTS reporting.usp_ArrearsBucketSummary;
DROP FUNCTION IF EXISTS dbo.fn_MonthlyRate;
DROP FUNCTION IF EXISTS reporting.fn_OfficerActiveLoans;
DROP FUNCTION IF EXISTS dbo.fn_AgeAt;
DROP FUNCTION IF EXISTS reporting.fn_BranchScorecard;
DROP TABLE IF EXISTS dbo.Practice_Loan26;
GO

-- Prerequisites: the reporting schema (chapter 20) and dbo.LoanIdList (chapter 25)
IF SCHEMA_ID(N'reporting') IS NULL
    EXEC (N'CREATE SCHEMA reporting');
IF TYPE_ID(N'dbo.LoanIdList') IS NULL
    EXEC (N'CREATE TYPE dbo.LoanIdList AS TABLE
            (LoanID INT NOT NULL PRIMARY KEY);');
GO

-- ------------------------------------------------------------
-- Correction 26.1
-- ------------------------------------------------------------

GO
CREATE OR ALTER PROCEDURE reporting.usp_ProductList
AS
BEGIN
    SET NOCOUNT ON;              -- no row-count message

    SELECT ProductCode, ProductName, BaseRate
    FROM dbo.Product
    ORDER BY BaseRate DESC;      -- highest rate first
END;
GO

EXEC reporting.usp_ProductList;
GO

-- ------------------------------------------------------------
-- Correction 26.2
-- ------------------------------------------------------------

GO
CREATE OR ALTER PROCEDURE reporting.usp_TopCustomersInCity
    @City NVARCHAR(40),          -- same type as Customer.City
    @TopN INT = 5                -- optional
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@TopN)
        CustomerID, FirstName, LastName, CreditScore
    FROM dbo.Customer
    WHERE City = @City
    ORDER BY CreditScore DESC, CustomerID;  -- ties by ID
END;
GO

EXEC reporting.usp_TopCustomersInCity @City = N'Leeds';
GO

-- ------------------------------------------------------------
-- Correction 26.3
-- ------------------------------------------------------------

GO
CREATE OR ALTER FUNCTION dbo.fn_MonthlyRate
(
    @AnnualRatePct DECIMAL(5,2)
)
RETURNS DECIMAL(9,6)
WITH SCHEMABINDING
AS
BEGIN
    RETURN @AnnualRatePct / 1200;   -- 12 months x 100 percent
END;
GO

SELECT
    ProductCode,
    BaseRate,
    dbo.fn_MonthlyRate(BaseRate) AS MonthlyRate
FROM dbo.Product
ORDER BY BaseRate DESC;
GO

-- ------------------------------------------------------------
-- Correction 26.4
-- ------------------------------------------------------------

GO
CREATE OR ALTER PROCEDURE reporting.usp_CustomerExposure
    @CustomerID  INT,
    @LoanCount   INT OUTPUT,
    @Outstanding DECIMAL(14,2) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        @LoanCount   = COUNT(*),
        @Outstanding = SUM(OutstandingBalance)
    FROM dbo.Loan
    WHERE CustomerID = @CustomerID;
END;
GO

DECLARE @n INT, @Total DECIMAL(14,2);

EXEC reporting.usp_CustomerExposure
    @CustomerID  = 21,
    @LoanCount   = @n OUTPUT,       -- OUTPUT in the call too
    @Outstanding = @Total OUTPUT;

SELECT @n AS Loans, @Total AS Outstanding;
GO

-- ------------------------------------------------------------
-- Correction 26.5
-- ------------------------------------------------------------

DROP TABLE IF EXISTS dbo.Practice_Loan26;
SELECT * INTO dbo.Practice_Loan26 FROM dbo.Loan;   -- 800 rows
GO

CREATE OR ALTER PROCEDURE reporting.usp_SetPracticeStatus
    @LoanID    INT,
    @NewStatus NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Practice_Loan26
                   WHERE LoanID = @LoanID)
        RETURN 1;                              -- unknown loan

    IF @NewStatus IS NULL
       OR @NewStatus NOT IN (N'Active', N'Repaid', N'Arrears',
                             N'Default', N'Written Off')
        RETURN 2;                              -- invalid status

    UPDATE dbo.Practice_Loan26
    SET LoanStatus = @NewStatus
    WHERE LoanID = @LoanID;

    RETURN 0;                                  -- success
END;
GO

DECLARE @rc1 INT, @rc2 INT, @rc3 INT;

EXEC @rc1 = reporting.usp_SetPracticeStatus 10999, N'Active';
EXEC @rc2 = reporting.usp_SetPracticeStatus 10007, N'Closed';
EXEC @rc3 = reporting.usp_SetPracticeStatus 10007, N'Default';

SELECT @rc1 AS Call1, @rc2 AS Call2, @rc3 AS Call3;

SELECT LoanID, LoanStatus
FROM dbo.Practice_Loan26
WHERE LoanID = 10007;
GO

-- ------------------------------------------------------------
-- Correction 26.6
-- ------------------------------------------------------------

GO
CREATE OR ALTER FUNCTION reporting.fn_OfficerActiveLoans
(
    @OfficerID INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT LoanID, OutstandingBalance
    FROM dbo.Loan
    WHERE OfficerID = @OfficerID
      AND LoanStatus = N'Active'
);
GO

SELECT
    o.OfficerID,
    o.FirstName + N' ' + o.LastName AS OfficerName,
    COUNT(x.LoanID) AS ActiveLoans,          -- 0 if no loans
    SUM(x.OutstandingBalance) AS ActiveBalance
FROM dbo.LoanOfficer AS o
OUTER APPLY reporting.fn_OfficerActiveLoans(o.OfficerID) AS x
WHERE o.BranchID = 5
GROUP BY o.OfficerID, o.FirstName, o.LastName
ORDER BY o.OfficerID;
GO

-- ------------------------------------------------------------
-- Correction 26.7
-- ------------------------------------------------------------

GO
CREATE OR ALTER FUNCTION reporting.fn_BranchScorecard
(
    @AsOfDate DATE
)
RETURNS @Card TABLE
(
    BranchID        INT           NOT NULL PRIMARY KEY,
    BranchName      NVARCHAR(60)  NOT NULL,
    OpenLoans       INT           NOT NULL,
    OpenBalance     DECIMAL(14,2) NOT NULL,
    OverdueLoans    INT           NULL,
    OverdueSharePct DECIMAL(5,2)  NULL
)
AS
BEGIN
    -- Step 1: the open book of each branch
    INSERT INTO @Card (BranchID, BranchName, OpenLoans, OpenBalance)
    SELECT b.BranchID, b.BranchName, COUNT(*),
           SUM(l.OutstandingBalance)
    FROM dbo.Branch AS b
    INNER JOIN dbo.Loan AS l
        ON l.BranchID = b.BranchID
    WHERE l.LoanStatus IN (N'Active', N'Arrears', N'Default')
    GROUP BY b.BranchID, b.BranchName;

    -- Step 2: open loans with an instalment overdue at @AsOfDate
    UPDATE c
    SET OverdueLoans =
        (SELECT COUNT(DISTINCT l.LoanID)
         FROM dbo.Loan AS l
         INNER JOIN dbo.Payment AS p
             ON p.LoanID = l.LoanID
         WHERE l.BranchID = c.BranchID
           AND l.LoanStatus IN (N'Active', N'Arrears', N'Default')
           AND p.DueDate < @AsOfDate
           AND (p.PaidDate IS NULL OR p.PaidDate > @AsOfDate))
    FROM @Card AS c;

    -- Step 3: the share, rounded to 2 decimals by the column type
    UPDATE @Card
    SET OverdueSharePct = OverdueLoans * 100.0 / OpenLoans;

    RETURN;
END;
GO

SELECT BranchID, BranchName, OpenLoans, OpenBalance,
       OverdueLoans, OverdueSharePct
FROM reporting.fn_BranchScorecard('2026-09-30')
ORDER BY BranchID;
GO

-- ------------------------------------------------------------
-- Correction 26.8
-- ------------------------------------------------------------

GO
CREATE OR ALTER PROCEDURE reporting.usp_ExposureByProductType
    @LoanIds dbo.LoanIdList READONLY,
    @Total   DECIMAL(14,2) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.ProductType,
        COUNT(*) AS Loans,
        SUM(l.OutstandingBalance) AS Outstanding
    FROM @LoanIds AS i
    INNER JOIN dbo.Loan AS l
        ON l.LoanID = i.LoanID
    INNER JOIN dbo.Product AS p
        ON p.ProductCode = l.ProductCode
    GROUP BY p.ProductType
    ORDER BY p.ProductType;

    SELECT @Total = SUM(l.OutstandingBalance)
    FROM @LoanIds AS i
    INNER JOIN dbo.Loan AS l
        ON l.LoanID = i.LoanID;
END;
GO

DECLARE @Ids dbo.LoanIdList, @GrandTotal DECIMAL(14,2);

INSERT INTO @Ids (LoanID)
SELECT LoanID FROM dbo.Loan WHERE LoanStatus = N'Default';

EXEC reporting.usp_ExposureByProductType
    @LoanIds = @Ids,
    @Total   = @GrandTotal OUTPUT;

SELECT @GrandTotal AS TotalOutstanding;
GO

-- ============================================================
-- Clean-up: remove every object this script created
-- ============================================================

DROP PROCEDURE IF EXISTS reporting.usp_ProductList;
DROP PROCEDURE IF EXISTS reporting.usp_TopCustomersInCity;
DROP PROCEDURE IF EXISTS reporting.usp_CustomerExposure;
DROP PROCEDURE IF EXISTS reporting.usp_SetPracticeStatus;
DROP PROCEDURE IF EXISTS reporting.usp_ExposureByProductType;
DROP PROCEDURE IF EXISTS reporting.usp_ArrearsBucketSummary;
DROP FUNCTION IF EXISTS dbo.fn_MonthlyRate;
DROP FUNCTION IF EXISTS reporting.fn_OfficerActiveLoans;
DROP FUNCTION IF EXISTS dbo.fn_AgeAt;
DROP FUNCTION IF EXISTS reporting.fn_BranchScorecard;
DROP TABLE IF EXISTS dbo.Practice_Loan26;
GO
