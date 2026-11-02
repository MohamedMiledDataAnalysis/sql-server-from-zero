/* SQL Server from Zero — Volume 1
   Chapter 01: Installing SQL Server and writing your first query
   Target: SQL Server 2025 (runs on 2022). */

-- 1. What a database is, and what SQL is for
-- Preview only: dbo.Customer exists after chapter 2. Uncomment then.
-- SELECT FirstName, LastName
-- FROM dbo.Customer
-- WHERE City = N'London';

-- 4. Your first query
SELECT 1 + 1;

-- 4. Your first query
SELECT 12 + 3 AS Addition,
       12 - 3 AS Subtraction,
       12 * 3 AS Multiplication,
       12 / 3 AS Division,
       12 % 5 AS Remainder;

-- 4. Your first query
SELECT 7 / 2 AS IntegerDivision,
       7 / 2.0 AS DecimalDivision;

-- 4. Your first query
SELECT 'Northbridge Lending' AS Company,
       N'Société Générale' AS UnicodeText;

-- 5. Asking the server about itself
SELECT @@VERSION AS VersionText;

SELECT @@SERVERNAME AS ServerName,
       SERVERPROPERTY('Edition') AS Edition,
       SERVERPROPERTY('ProductVersion') AS ProductVersion,
       DB_NAME() AS CurrentDatabase,
       SUSER_SNAME() AS CurrentLogin;

-- 5. Asking the server about itself
SELECT GETDATE() AS NowDateTime,
       SYSDATETIME() AS NowPrecise,
       CAST(GETDATE() AS DATE) AS Today;

-- 6. Comments, batches and GO
-- A line comment: everything after the two dashes is ignored.
SELECT 100 * 1.05 AS PrincipalWithInterest;  -- 5 % interest

/* A block comment
   can run over
   several lines. */
SELECT 'Done' AS Status;

-- 6. Comments, batches and GO
SELECT 'First batch' AS Message;
GO
SELECT 'Second batch' AS Message;
GO

-- 6. Comments, batches and GO
SELECT 'Repeated' AS Message;
GO 3

-- 7. Reading error messages
-- Deliberate error 8134: remove the two dashes to see it.
-- SELECT 100 / 0 AS Impossible;

-- 7. Reading error messages
-- Deliberate error, kept as a comment so the rest of the script runs.
-- Remove the two dashes to see errors 105 and 102:
-- SELECT 'Hello AS Greeting;

-- Applied example
/* Northbridge Lending — environment check
   Author: <your name>
   Purpose: confirm the SQL Server installation */
SELECT @@SERVERNAME AS ServerName,
       SERVERPROPERTY('Edition') AS Edition,
       SERVERPROPERTY('ProductVersion') AS ProductVersion,
       CAST(GETDATE() AS DATE) AS CheckDate;

-- Applied example
SELECT 18000 * 7.9 / 100 / 12 AS Version1,
       18000 * 7.9 / (100 * 12) AS Version2;
