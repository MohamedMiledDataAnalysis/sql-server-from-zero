/* SQL Server from Zero — Volume 1
   Chapter 26: Stored procedures and functions
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

/* This script creates stored procedures and functions in the reporting
   and dbo schemas. It changes no table data. The statement marked
   "FAILS ON PURPOSE" shows an error message from the book; it is
   commented out so that the script runs end to end. */

-- Start from a clean state so that the script can run more than once
-- Prerequisites: the reporting schema (chapter 20) and dbo.LoanIdList (chapter 25)
IF SCHEMA_ID(N'reporting') IS NULL
    EXEC (N'CREATE SCHEMA reporting');
IF TYPE_ID(N'dbo.LoanIdList') IS NULL
    EXEC (N'CREATE TYPE dbo.LoanIdList AS TABLE
            (LoanID INT NOT NULL PRIMARY KEY);');
GO

DROP PROCEDURE IF EXISTS reporting.usp_LoanStatusSummary;
DROP PROCEDURE IF EXISTS reporting.usp_LoansByBranch;
DROP PROCEDURE IF EXISTS reporting.usp_BranchExposure;
DROP PROCEDURE IF EXISTS reporting.usp_GetLoan;
DROP PROCEDURE IF EXISTS reporting.usp_LoanListSummary;
DROP PROCEDURE IF EXISTS reporting.usp_MonthlyArrearsReport;
DROP FUNCTION IF EXISTS dbo.fn_GradeFromScore;
DROP FUNCTION IF EXISTS dbo.fn_DaysSince;
DROP FUNCTION IF EXISTS reporting.fn_LargestLoans;
DROP FUNCTION IF EXISTS reporting.fn_PaymentProfile;
DROP FUNCTION IF EXISTS dbo.fn_DpdBucket;
DROP TABLE IF EXISTS #Arrears;
GO

-- ============================================================
-- 1. Your first stored procedure
-- ============================================================

GO
CREATE PROCEDURE reporting.usp_LoanStatusSummary
AS
BEGIN
    SELECT
        LoanStatus,
        COUNT(*) AS Loans,
        SUM(OutstandingBalance) AS Outstanding
    FROM dbo.Loan
    GROUP BY LoanStatus
    ORDER BY LoanStatus;
END;
GO

EXEC reporting.usp_LoanStatusSummary;
GO

-- ============================================================
-- 2. Input parameters and default values
-- ============================================================

GO
CREATE PROCEDURE reporting.usp_LoansByBranch
    @BranchID   INT,
    @LoanStatus NVARCHAR(20) = N'Active',
    @TopN       INT = 5
AS
BEGIN
    SELECT TOP (@TopN)
        LoanID,
        ProductCode,
        OutstandingBalance
    FROM dbo.Loan
    WHERE BranchID = @BranchID
      AND LoanStatus = @LoanStatus
    ORDER BY OutstandingBalance DESC, LoanID;
END;
GO

EXEC reporting.usp_LoansByBranch 7;
GO

EXEC reporting.usp_LoansByBranch
    @BranchID   = 7,
    @LoanStatus = N'Default';
GO

-- FAILS ON PURPOSE: Msg 201, @BranchID not supplied
-- EXEC reporting.usp_LoansByBranch @LoanStatus = N'Default';
GO

-- ============================================================
-- 3. OUTPUT parameters
-- ============================================================

GO
CREATE PROCEDURE reporting.usp_BranchExposure
    @BranchID    INT,
    @OpenLoans   INT OUTPUT,
    @OpenBalance DECIMAL(14,2) OUTPUT
AS
BEGIN
    SELECT
        @OpenLoans   = COUNT(*),
        @OpenBalance = SUM(OutstandingBalance)
    FROM dbo.Loan
    WHERE BranchID = @BranchID
      AND LoanStatus <> N'Repaid';
END;
GO

DECLARE @Loans INT,
        @Balance DECIMAL(14,2);

EXEC reporting.usp_BranchExposure
    @BranchID    = 3,
    @OpenLoans   = @Loans OUTPUT,
    @OpenBalance = @Balance OUTPUT;

SELECT @Loans AS OpenLoans, @Balance AS OpenBalance;
GO

-- ============================================================
-- 4. RETURN codes
-- ============================================================

GO
CREATE PROCEDURE reporting.usp_GetLoan
    @LoanID INT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.Loan WHERE LoanID = @LoanID)
        RETURN 1;               -- 1 = loan not found

    SELECT LoanID, CustomerID, ProductCode, LoanStatus,
           OutstandingBalance
    FROM dbo.Loan
    WHERE LoanID = @LoanID;

    RETURN 0;                   -- 0 = success
END;
GO

DECLARE @rc INT;

EXEC @rc = reporting.usp_GetLoan @LoanID = 10999;
SELECT @rc AS ReturnCode;

EXEC @rc = reporting.usp_GetLoan @LoanID = 10001;
SELECT @rc AS ReturnCode;
GO

-- ============================================================
-- 5. Changing and dropping procedures; table-valued parameters
-- ============================================================

GO
CREATE OR ALTER PROCEDURE reporting.usp_LoanStatusSummary
AS
BEGIN
    SET NOCOUNT ON;             -- no "(n rows affected)" message

    SELECT
        LoanStatus,
        COUNT(*) AS Loans,
        SUM(OutstandingBalance) AS Outstanding
    FROM dbo.Loan
    GROUP BY LoanStatus
    ORDER BY LoanStatus;
END;
GO

EXEC reporting.usp_LoanStatusSummary;
GO

DROP PROCEDURE IF EXISTS reporting.usp_GetLoan;
GO

-- ============================================================
-- 6. Scalar functions and determinism
-- ============================================================

GO
CREATE OR ALTER FUNCTION dbo.fn_GradeFromScore
(
    @Score SMALLINT
)
RETURNS CHAR(1)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE
               WHEN @Score >= 850 THEN 'A'
               WHEN @Score >= 750 THEN 'B'
               WHEN @Score >= 650 THEN 'C'
               WHEN @Score >= 550 THEN 'D'
               ELSE 'E'
           END;
END;
GO

SELECT TOP (6)
    CustomerID,
    CreditScore,
    dbo.fn_GradeFromScore(CreditScore) AS Grade
FROM dbo.Customer
ORDER BY CustomerID;
GO

GO
CREATE OR ALTER FUNCTION dbo.fn_DaysSince
(
    @FromDate DATE
)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
    RETURN DATEDIFF(day, @FromDate, CAST(GETDATE() AS DATE));
END;
GO

SELECT
    name,
    OBJECTPROPERTY(object_id, 'IsDeterministic') AS IsDeterministic
FROM sys.objects
WHERE object_id IN (OBJECT_ID(N'dbo.fn_GradeFromScore'),
                    OBJECT_ID(N'dbo.fn_DaysSince'))
ORDER BY name;
GO

-- ============================================================
-- 7. Inline table-valued functions
-- ============================================================

GO
CREATE OR ALTER FUNCTION reporting.fn_LargestLoans
(
    @BranchID INT,
    @TopN     INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (@TopN)
        LoanID,
        ProductCode,
        OutstandingBalance
    FROM dbo.Loan
    WHERE BranchID = @BranchID
      AND LoanStatus = N'Active'
    ORDER BY OutstandingBalance DESC, LoanID
);
GO

SELECT LoanID, ProductCode, OutstandingBalance
FROM reporting.fn_LargestLoans(7, 3)
ORDER BY OutstandingBalance DESC;
GO

SELECT
    b.BranchID,
    b.BranchName,
    x.LoanID,
    x.OutstandingBalance
FROM dbo.Branch AS b
CROSS APPLY reporting.fn_LargestLoans(b.BranchID, 1) AS x
ORDER BY b.BranchID;
GO

-- ============================================================
-- 8. Multi-statement table-valued functions and DROP FUNCTION
-- ============================================================

GO
CREATE OR ALTER FUNCTION reporting.fn_PaymentProfile
(
    @LoanID INT
)
RETURNS @Profile TABLE
(
    LoanID       INT           NOT NULL,
    Instalments  INT           NOT NULL,
    PaidOnTime   INT           NOT NULL,
    PaidLate     INT           NOT NULL,
    Missed       INT           NOT NULL,
    AmountDue    DECIMAL(14,2) NOT NULL,
    AmountPaid   DECIMAL(14,2) NOT NULL,
    Rating       NVARCHAR(20)  NULL
)
AS
BEGIN
    -- Step 1: an unknown loan returns an empty table
    IF NOT EXISTS (SELECT 1 FROM dbo.Loan WHERE LoanID = @LoanID)
        RETURN;

    -- Step 2: count and add up the instalments
    INSERT INTO @Profile
        (LoanID, Instalments, PaidOnTime, PaidLate, Missed,
         AmountDue, AmountPaid)
    SELECT
        @LoanID,
        COUNT(*),
        SUM(CASE WHEN DaysLate = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN DaysLate > 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN PaidDate IS NULL THEN 1 ELSE 0 END),
        SUM(AmountDue),
        SUM(AmountPaid)
    FROM dbo.Payment
    WHERE LoanID = @LoanID;

    -- Step 3: rate the history
    UPDATE @Profile
    SET Rating = CASE
                     WHEN Missed > 0   THEN N'Missed payments'
                     WHEN PaidLate > 0 THEN N'Late payer'
                     ELSE N'Clean'
                 END;

    RETURN;
END;
GO

SELECT p.LoanID, p.Instalments, p.PaidLate, p.Missed,
       p.AmountPaid, p.Rating
FROM dbo.Loan AS l
CROSS APPLY reporting.fn_PaymentProfile(l.LoanID) AS p
WHERE l.LoanID IN (10001, 10002, 10076)
ORDER BY p.LoanID;
GO

DROP FUNCTION IF EXISTS dbo.fn_DaysSince;
GO

-- ============================================================
-- Applied example
-- ============================================================

GO
CREATE OR ALTER FUNCTION dbo.fn_DpdBucket
(
    @DaysPastDue INT
)
RETURNS VARCHAR(5)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE
               WHEN @DaysPastDue < 30 THEN '1-29'
               WHEN @DaysPastDue < 60 THEN '30-59'
               WHEN @DaysPastDue < 90 THEN '60-89'
               ELSE '90+'
           END;
END;
GO

GO
CREATE OR ALTER PROCEDURE reporting.usp_MonthlyArrearsReport
    @AsOfDate  DATE = '2026-09-30',
    @BranchID  INT  = NULL,           -- NULL = all branches
    @LoanCount INT  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Return code 1: no date, or a date after the snapshot
    IF @AsOfDate IS NULL OR @AsOfDate > '2026-09-30'
        RETURN 1;

    -- Return code 2: a branch that does not exist
    IF @BranchID IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.Branch
                       WHERE BranchID = @BranchID)
        RETURN 2;

    SELECT
        l.LoanID,
        b.BranchName,
        l.LoanStatus,
        COUNT(*) AS OverdueInstalments,
        SUM(p.AmountDue) AS OverdueAmount,
        MIN(p.DueDate) AS OldestDueDate,
        DATEDIFF(day, MIN(p.DueDate), @AsOfDate) AS DaysPastDue,
        dbo.fn_DpdBucket(DATEDIFF(day, MIN(p.DueDate), @AsOfDate))
            AS Bucket
    FROM dbo.Payment AS p
    INNER JOIN dbo.Loan AS l
        ON l.LoanID = p.LoanID
    INNER JOIN dbo.Branch AS b
        ON b.BranchID = l.BranchID
    WHERE p.DueDate < @AsOfDate
      AND (p.PaidDate IS NULL OR p.PaidDate > @AsOfDate)
      AND l.LoanStatus <> N'Written Off'
      AND (@BranchID IS NULL OR l.BranchID = @BranchID)
    GROUP BY l.LoanID, b.BranchName, l.LoanStatus
    ORDER BY DaysPastDue DESC, l.LoanID;

    SET @LoanCount = @@ROWCOUNT;      -- rows of the SELECT above
    RETURN 0;
END;
GO

DECLARE @rc INT, @Loans INT;

EXEC @rc = reporting.usp_MonthlyArrearsReport
    @AsOfDate  = '2026-09-30',
    @LoanCount = @Loans OUTPUT;

SELECT @rc AS ReturnCode, @Loans AS LoansInArrears;
GO

-- One branch (mentioned at the end of step 3)
DECLARE @rc INT, @Loans INT;

EXEC @rc = reporting.usp_MonthlyArrearsReport
    @BranchID  = 2,
    @LoanCount = @Loans OUTPUT;

SELECT @rc AS ReturnCode, @Loans AS LoansInArrears;
GO

DROP TABLE IF EXISTS #Arrears;

CREATE TABLE #Arrears
(
    LoanID             INT           NOT NULL,
    BranchName         NVARCHAR(60)  NOT NULL,
    LoanStatus         NVARCHAR(20)  NOT NULL,
    OverdueInstalments INT           NOT NULL,
    OverdueAmount      DECIMAL(38,2) NOT NULL,
    OldestDueDate      DATE          NOT NULL,
    DaysPastDue        INT           NOT NULL,
    Bucket             VARCHAR(5)    NOT NULL
);

INSERT INTO #Arrears
EXEC reporting.usp_MonthlyArrearsReport @AsOfDate = '2026-06-30';

SELECT Bucket, COUNT(*) AS Loans, SUM(OverdueAmount) AS Overdue
FROM #Arrears
GROUP BY Bucket
ORDER BY Bucket;
GO

-- The same summary for 30 September 2026
TRUNCATE TABLE #Arrears;

INSERT INTO #Arrears
EXEC reporting.usp_MonthlyArrearsReport @AsOfDate = '2026-09-30';

SELECT Bucket, COUNT(*) AS Loans, SUM(OverdueAmount) AS Overdue
FROM #Arrears
GROUP BY Bucket
ORDER BY Bucket;
GO

-- ============================================================
-- Clean-up: remove every object this script created
-- ============================================================
DROP PROCEDURE IF EXISTS reporting.usp_LoanStatusSummary;
DROP PROCEDURE IF EXISTS reporting.usp_LoansByBranch;
DROP PROCEDURE IF EXISTS reporting.usp_BranchExposure;
DROP PROCEDURE IF EXISTS reporting.usp_GetLoan;
DROP PROCEDURE IF EXISTS reporting.usp_LoanListSummary;
DROP PROCEDURE IF EXISTS reporting.usp_MonthlyArrearsReport;
DROP FUNCTION IF EXISTS dbo.fn_GradeFromScore;
DROP FUNCTION IF EXISTS dbo.fn_DaysSince;
DROP FUNCTION IF EXISTS reporting.fn_LargestLoans;
DROP FUNCTION IF EXISTS reporting.fn_PaymentProfile;
DROP FUNCTION IF EXISTS dbo.fn_DpdBucket;
DROP TABLE IF EXISTS #Arrears;
GO
