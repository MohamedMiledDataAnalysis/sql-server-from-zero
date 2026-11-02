/* SQL Server from Zero — Volume 1
   Chapter 18: EXEC, sp_executesql and dynamic SQL
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Correction 18.1
-- 1. Hold the statement in a Unicode variable
DECLARE @sql NVARCHAR(MAX) =
    N'SELECT COUNT(*) AS PaymentCount FROM dbo.Payment;';

PRINT @sql;      -- 2. Show the text in the Messages tab
EXEC (@sql);     -- 3. Run it; the parentheses are required
GO

-- Step by step

-- Correction 18.2
DECLARE @City NVARCHAR(40) = N'Glasgow';
DECLARE @sql  NVARCHAR(MAX);

SET @sql = N'SELECT COUNT(*) AS CustomerCount '
         + N'FROM dbo.Customer '
         -- N''' = the text N' (opening quote of the value)
         + N'WHERE City = N''' + @City
         -- ''' = the closing quote, then the semicolon
         + N''';';

PRINT @sql;
EXEC (@sql);
GO

-- Step by step

-- Correction 18.3
SELECT QUOTENAME(N'Payment')         AS A,  -- plain name
       QUOTENAME(N'Due Date')        AS B,  -- name with a space
       QUOTENAME(N'[Weird]')         AS C,  -- name with brackets
       QUOTENAME(N'Cardiff', '''')   AS D;  -- quote as delimiter
GO

-- Step by step

-- Correction 18.4
DECLARE @sql NVARCHAR(MAX) =
      N'SELECT @Paid   = SUM(AmountPaid), '
      -- count only the rows where the instalment was missed
    + N'       @Missed = SUM(CASE WHEN PaidDate IS NULL '
    + N'                          THEN 1 ELSE 0 END) '
    + N'FROM dbo.Payment '
    + N'WHERE LoanID = @LoanID;';

DECLARE @TotalPaid DECIMAL(14,2);   -- receives @Paid
DECLARE @MissedCnt INT;             -- receives @Missed

EXEC sp_executesql
    @sql,
    N'@LoanID INT, @Paid DECIMAL(14,2) OUTPUT,
      @Missed INT OUTPUT',
    @LoanID = 10002,
    @Paid   = @TotalPaid OUTPUT,    -- OUTPUT on the call too
    @Missed = @MissedCnt OUTPUT;

SELECT @TotalPaid AS TotalPaid, @MissedCnt AS MissedInstalments;
GO

-- Step by step

-- Correction 18.5
DECLARE @TableName SYSNAME = N'CreditRating';
DECLARE @sql       NVARCHAR(MAX);

-- 1. Whitelist: the table must exist in dbo as a base table
IF NOT EXISTS (SELECT 1
               FROM INFORMATION_SCHEMA.TABLES
               WHERE TABLE_SCHEMA = N'dbo'
                 AND TABLE_NAME   = @TableName
                 AND TABLE_TYPE   = 'BASE TABLE')
BEGIN
    PRINT N'Unknown table: dbo.' + @TableName;
    RETURN;                              -- stop the batch
END;

-- 2. Build the statement with a quoted identifier
SET @sql = N'SELECT COUNT(*) AS RowCnt FROM dbo.'
         + QUOTENAME(@TableName) + N';';

PRINT @sql;
EXEC (@sql);                             -- 3. Run it
GO

-- Step by step

-- Correction 18.6
DECLARE @ByType TABLE (
    ProductType    NVARCHAR(20),
    LoanCount      INT,
    TotalPrincipal DECIMAL(14,2)
);

INSERT INTO @ByType (ProductType, LoanCount, TotalPrincipal)
EXEC sp_executesql
    N'SELECT p.ProductType, COUNT(*), SUM(l.Principal)
      FROM dbo.Loan AS l
      INNER JOIN dbo.Product AS p
          ON p.ProductCode = l.ProductCode
      GROUP BY p.ProductType;';

-- Work on the captured rows like on any table
SELECT ProductType, LoanCount, TotalPrincipal
FROM @ByType
WHERE LoanCount > 150
ORDER BY LoanCount DESC;
GO

-- Step by step

-- Correction 18.7
-- Exercise 18.7: the script as given; it concatenates the value into
-- the statement (open to injection), so it is left commented out.
-- DECLARE @Surname NVARCHAR(40) = N'Hill';
-- DECLARE @sql NVARCHAR(MAX) =
--       N'SELECT OfficerID, FirstName, LastName, BranchID '
--     + N'FROM dbo.LoanOfficer WHERE LastName = N'''
--     + @Surname + N''' ORDER BY OfficerID;';
-- EXEC (@sql);

-- The safe version.
DECLARE @Surname NVARCHAR(40) = N'x'' OR 1 = 1 --';
DECLARE @sql NVARCHAR(MAX) =
      N'SELECT OfficerID, FirstName, LastName, BranchID '
    + N'FROM dbo.LoanOfficer '
    + N'WHERE LastName = @Surname '      -- placeholder, no quotes
    + N'ORDER BY OfficerID;';

EXEC sp_executesql
    @sql,
    N'@Surname NVARCHAR(40)',            -- same type as LastName
    @Surname = @Surname;                 -- inner = outer
GO

-- Step by step

-- Correction 18.8
DECLARE @BranchID   INT           = 5;
DECLARE @MinBalance DECIMAL(12,2) = 200000;
DECLARE @sql        NVARCHAR(MAX);

SET @sql = N'SELECT COUNT(*) AS LoanCount, '
         + N'SUM(OutstandingBalance) AS Balance '
         + N'FROM dbo.Loan '
         + N'WHERE 1 = 1';   -- always true: each filter adds AND

IF @BranchID IS NOT NULL
    SET @sql += N' AND BranchID = @BranchID';

IF @MinBalance IS NOT NULL
    SET @sql += N' AND OutstandingBalance >= @MinBalance';

SET @sql += N';';

PRINT @sql;

EXEC sp_executesql
    @sql,
    N'@BranchID INT, @MinBalance DECIMAL(12,2)',
    @BranchID   = @BranchID,
    @MinBalance = @MinBalance;
GO

-- Step by step

-- These solutions read data only: no clean-up is needed.
