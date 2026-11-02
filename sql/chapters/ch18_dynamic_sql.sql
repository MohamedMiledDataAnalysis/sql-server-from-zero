/* SQL Server from Zero — Volume 1
   Chapter 18: EXEC, sp_executesql and dynamic SQL
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- 1. Running stored procedures with EXEC
USE NorthbridgeLending;
GO
-- Pass the table name by position (first parameter of sp_help)
EXEC sp_help N'dbo.Branch';

-- The same call, naming the parameter explicitly
EXEC sp_help @objname = N'dbo.Branch';
GO
-- Every session on the server
EXEC sp_who;

-- Only the sessions that are running something now
EXEC sp_who @loginame = 'active';

-- The session ID of this query window
SELECT @@SPID AS MySessionID;
GO
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- SELECT 1 AS Step;
-- sp_help N'dbo.Branch';   -- not the first statement: fails
GO

-- 2. Building a statement as a string: EXEC (@sql)
DECLARE @sql NVARCHAR(MAX);

SET @sql = N'SELECT COUNT(*) AS LoanCount FROM dbo.Loan;';

PRINT @sql;        -- shows the text in the Messages tab
EXEC (@sql);       -- runs the text as a batch
GO
DECLARE @Status NVARCHAR(20) = N'Arrears';
DECLARE @sql    NVARCHAR(MAX);

SET @sql = N'SELECT COUNT(*) AS LoanCount '
         + N'FROM dbo.Loan '
         + N'WHERE LoanStatus = N''' + @Status + N''';';

PRINT @sql;
EXEC (@sql);
GO
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- DECLARE @Status NVARCHAR(20) = N'Arrears';
-- 
-- EXEC (N'SELECT COUNT(*) FROM dbo.Loan WHERE LoanStatus = @Status;');
GO
-- Created inside: gone afterwards
EXEC (N'SELECT TOP (3) LoanID INTO #Inner FROM dbo.Loan
        ORDER BY LoanID;');
-- Fails on purpose with Msg 208: #Inner ended with the dynamic batch.
-- SELECT * FROM #Inner;            -- fails
GO
-- Created outside: visible inside
SELECT TOP (3) LoanID, Principal
INTO #Outer
FROM dbo.Loan
ORDER BY LoanID;

EXEC (N'SELECT LoanID, Principal FROM #Outer ORDER BY LoanID;');

DROP TABLE #Outer;
GO
EXEC (N'USE master; SELECT DB_NAME() AS InsideDatabase;');
SELECT DB_NAME() AS OutsideDatabase;
GO
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- DECLARE @sql NVARCHAR(MAX) = N'SELECT COUNT(*) FROM dbo.Loan;';
-- EXEC @sql;      -- parentheses forgotten
GO

-- 3. Table and column names: QUOTENAME and the catalogue
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- DECLARE @TableName SYSNAME = N'Branch';
-- SELECT COUNT(*) FROM @TableName;     -- fails
GO
SELECT QUOTENAME(N'Loan')           AS Plain,
       QUOTENAME(N'Loan Status')    AS WithSpace,
       QUOTENAME(N'Odd]Name')       AS WithBracket,
       QUOTENAME(N'Okafor', '''')   AS AsLiteral;
GO
DECLARE @SchemaName SYSNAME = N'dbo';
DECLARE @TableName  SYSNAME = N'Collateral';
DECLARE @sql        NVARCHAR(MAX);

IF NOT EXISTS (SELECT 1
               FROM INFORMATION_SCHEMA.TABLES
               WHERE TABLE_SCHEMA = @SchemaName
                 AND TABLE_NAME   = @TableName
                 AND TABLE_TYPE   = 'BASE TABLE')
BEGIN
    PRINT N'Unknown table: ' + @SchemaName + N'.' + @TableName;
    RETURN;                          -- stop the batch here
END;

SET @sql = N'SELECT COUNT(*) AS RowCnt FROM '
         + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName)
         + N';';

PRINT @sql;
EXEC (@sql);
GO
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- EXEC (N'SELECT COUNT(*) FROM ' + QUOTENAME(@TableName) + N';');
GO

-- 4. Parameterised dynamic SQL with sp_executesql
DECLARE @sql NVARCHAR(MAX) =
      N'SELECT COUNT(*)                AS LoanCount, '
    + N'       SUM(OutstandingBalance) AS Balance '
    + N'FROM dbo.Loan '
    + N'WHERE LoanStatus = @Status;';

EXEC sp_executesql
    @sql,                            -- the statement
    N'@Status NVARCHAR(20)',         -- its parameter list
    @Status = N'Arrears';            -- the value
GO
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- DECLARE @sql VARCHAR(200) = 'SELECT COUNT(*) FROM dbo.Loan;';
-- EXEC sp_executesql @sql;
GO

-- 5. Returning values: OUTPUT parameters
DECLARE @sql NVARCHAR(MAX) =
      N'SELECT @LoanCount = COUNT(*), '
    + N'       @Balance   = SUM(OutstandingBalance) '
    + N'FROM dbo.Loan '
    + N'WHERE LoanStatus = @Status;';

DECLARE @n   INT;
DECLARE @bal DECIMAL(14,2);

EXEC sp_executesql
    @sql,
    N'@Status NVARCHAR(20), @LoanCount INT OUTPUT,
      @Balance DECIMAL(14,2) OUTPUT',
    @Status    = N'Default',
    @LoanCount = @n   OUTPUT,        -- receive into @n
    @Balance   = @bal OUTPUT;        -- receive into @bal

SELECT @n AS DefaultLoans, @bal AS DefaultBalance;
GO

-- 6. SQL injection, and how parameters prevent it
DECLARE @SearchName NVARCHAR(40) = N'Okafor';
DECLARE @sql NVARCHAR(MAX) =
      N'SELECT CustomerID, FirstName, LastName, City '
    + N'FROM dbo.Customer '
    + N'WHERE LastName = N''' + @SearchName + N''' '
    + N'ORDER BY CustomerID;';

PRINT @sql;
EXEC (@sql);
GO
DECLARE @SearchName NVARCHAR(40) = N'x'' OR 1 = 1 --';
DECLARE @sql NVARCHAR(MAX) =
      N'SELECT CustomerID, FirstName, LastName, City '
    + N'FROM dbo.Customer '
    + N'WHERE LastName = N''' + @SearchName + N''' '
    + N'ORDER BY CustomerID;';

PRINT @sql;
EXEC (@sql);
GO
DECLARE @SearchName NVARCHAR(40) = N'x'' OR 1 = 1 --';
DECLARE @sql NVARCHAR(MAX) =
      N'SELECT CustomerID, FirstName, LastName, City '
    + N'FROM dbo.Customer '
    + N'WHERE LastName = @Name '
    + N'ORDER BY CustomerID;';

EXEC sp_executesql
    @sql,
    N'@Name NVARCHAR(40)',
    @Name = @SearchName;
GO

-- 7. Capturing results with INSERT … EXEC
DECLARE @StatusCounts TABLE (
    LoanStatus NVARCHAR(20),
    LoanCount  INT,
    Balance    DECIMAL(14,2)
);

INSERT INTO @StatusCounts (LoanStatus, LoanCount, Balance)
EXEC sp_executesql
    N'SELECT LoanStatus, COUNT(*), SUM(OutstandingBalance)
      FROM dbo.Loan
      GROUP BY LoanStatus;';

SELECT LoanStatus,
       LoanCount,
       Balance,
       CAST(LoanCount * 100.0 / 800 AS DECIMAL(5,2)) AS PctOfLoans
FROM @StatusCounts
ORDER BY LoanCount DESC;
GO

-- Applied example

-- Step 1. Declare the inputs and validate the column
DECLARE @GroupColumn SYSNAME      = N'ProductCode';
DECLARE @Status      NVARCHAR(20) = N'Default';

IF NOT EXISTS (SELECT 1
               FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = N'dbo'
                 AND TABLE_NAME   = N'Loan'
                 AND COLUMN_NAME  = @GroupColumn)
BEGIN
    PRINT N'Column not found in dbo.Loan: ' + @GroupColumn;
    RETURN;
END;

-- Step 2. Build the statement and print it
DECLARE @sql NVARCHAR(MAX) =
      N'SELECT ' + QUOTENAME(@GroupColumn) + N' AS GroupValue, '
    + N'       COUNT(*)                AS LoanCount, '
    + N'       SUM(OutstandingBalance) AS Balance '
    + N'FROM dbo.Loan '
    + N'WHERE LoanStatus = @Status '
    + N'GROUP BY ' + QUOTENAME(@GroupColumn) + N';';

PRINT @sql;

-- Step 3. Capture the rows with INSERT … EXEC
DECLARE @Report TABLE (
    GroupValue NVARCHAR(40),
    LoanCount  INT,
    Balance    DECIMAL(14,2)
);

INSERT INTO @Report (GroupValue, LoanCount, Balance)
EXEC sp_executesql
    @sql,
    N'@Status NVARCHAR(20)',
    @Status = @Status;

-- Step 4. Compute the shares and show the report
DECLARE @Total DECIMAL(14,2) = (SELECT SUM(Balance) FROM @Report);

SELECT GroupValue,
       LoanCount,
       Balance,
       CAST(ROUND(Balance * 100 / @Total, 2) AS DECIMAL(5,2))
           AS PctOfBalance
FROM @Report
ORDER BY GroupValue;
GO

-- Step 5. Reuse the script with another column
--   Change the first line of step 1 to N'BranchID' and run steps 1-4 again.

-- Step 6. Prove that the script refuses a bad column
--   Set the first line of step 1 to
--   N'LoanStatus; DROP TABLE dbo.Payment' and run steps 1-4 again:
--   the check prints a message and nothing else runs.

-- This script reads data only: no clean-up is needed.
