/* SQL Server from Zero — Volume 1
   Chapter 10: Variables, PRINT and session settings
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Correction 10.1

DECLARE @ProductCode VARCHAR(10) = 'PL-STD';   -- same type as column

SELECT
    COUNT(*)       AS Loans,
    SUM(Principal) AS TotalPrincipal
FROM dbo.Loan
WHERE ProductCode = @ProductCode;
GO


-- Correction 10.2

DECLARE @CustomerID INT = 128;
DECLARE @FirstName NVARCHAR(40),
        @LastName  NVARCHAR(40),
        @City      NVARCHAR(40);

SELECT @FirstName = FirstName,
       @LastName  = LastName,
       @City      = City
FROM dbo.Customer
WHERE CustomerID = @CustomerID;          -- primary key: one row

PRINT CONCAT('Customer ', @CustomerID, ': ',
             @FirstName, ' ', @LastName, ', ', @City);
GO


-- Correction 10.3

DECLARE @AsOfDate  DATE = '2026-09-30';
DECLARE @YearStart DATE = '2026-01-01';

PRINT CONCAT('Snapshot: ', CONVERT(VARCHAR(10), @AsOfDate, 103));
PRINT CONCAT('Days since 1 January: ',
             DATEDIFF(DAY, @YearStart, @AsOfDate));
GO


-- Correction 10.4

DECLARE @WrittenOff TABLE
(
    LoanID             INT           NOT NULL PRIMARY KEY,
    BranchID           INT           NOT NULL,
    OutstandingBalance DECIMAL(12,2) NOT NULL
);

INSERT INTO @WrittenOff (LoanID, BranchID, OutstandingBalance)
SELECT LoanID, BranchID, OutstandingBalance
FROM dbo.Loan
WHERE LoanStatus = N'Written Off';       -- 20 rows

SELECT
    b.BranchName,
    COUNT(*)                  AS Loans,
    SUM(w.OutstandingBalance) AS Balance
FROM @WrittenOff AS w                    -- alias, not @WrittenOff.col
INNER JOIN dbo.Branch AS b
    ON b.BranchID = w.BranchID
GROUP BY b.BranchName
ORDER BY b.BranchName;
GO


-- Correction 10.5

DECLARE @HighRate INT;

SELECT LoanID, ProductCode, InterestRate
FROM dbo.Loan
WHERE InterestRate > 10.00;

SET @HighRate = @@ROWCOUNT;              -- the very next statement

PRINT CONCAT('High-rate loans: ', @HighRate);
PRINT CONCAT('Check: ', @HighRate);      -- the variable keeps 11
GO


-- Correction 10.6

SET DATEFORMAT dmy;                      -- day, month, year
SELECT
    CAST('05/06/2026' AS DATE)     AS A, -- read as 5 June
    CAST('2026-06-05' AS DATETIME) AS B, -- read as y-d-m: 6 May
    CAST('20260605' AS DATETIME)   AS C; -- always 5 June
SET DATEFORMAT mdy;                      -- back to the default
GO


-- Correction 10.7

DECLARE @LastName NVARCHAR(40);

SELECT @LastName = LastName
FROM dbo.Customer
WHERE CustomerID = 42;
PRINT CONCAT('Customer 42: ', @LastName);

SELECT @LastName = LastName
FROM dbo.Customer
WHERE CustomerID = 9999;                 -- no row: no assignment
PRINT CONCAT('Customer 9999: ', @LastName);
GO

DECLARE @LastName NVARCHAR(40);

SET @LastName = (SELECT LastName
                 FROM dbo.Customer
                 WHERE CustomerID = 42);
PRINT CONCAT('Customer 42: ', COALESCE(@LastName, N'not found'));

SET @LastName = (SELECT LastName
                 FROM dbo.Customer
                 WHERE CustomerID = 9999);   -- no row: NULL
PRINT CONCAT('Customer 9999: ', COALESCE(@LastName, N'not found'));
GO


-- Correction 10.8

DROP TABLE IF EXISTS #NonPerforming;

SELECT
    BranchID,
    COUNT(*)                AS Loans,  -- names the new column
    SUM(OutstandingBalance) AS Balance
INTO #NonPerforming
FROM dbo.Loan
WHERE LoanStatus IN (N'Arrears', N'Default', N'Written Off')
GROUP BY BranchID;
GO

SELECT b.BranchName, n.Loans, n.Balance
FROM #NonPerforming AS n
INNER JOIN dbo.Branch AS b
    ON b.BranchID = n.BranchID
ORDER BY n.Balance DESC;

DROP TABLE IF EXISTS #NonPerforming;     -- tidy up tempdb
GO


