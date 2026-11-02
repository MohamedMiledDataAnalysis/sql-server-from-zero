/* SQL Server from Zero — Volume 1
   Chapter 15: Loading files: BULK INSERT, OPENROWSET and bcp
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

/* Before running this script, copy the CSV files of data/csv:
     Windows : to C:\NorthbridgeData\
               mkdir C:\NorthbridgeData
               copy data\csv\*.csv C:\NorthbridgeData\
     Docker  : to /var/opt/mssql/data/import/ inside the container
               docker cp data/csv/. northbridge-sql:/var/opt/mssql/data/import/
               docker exec -u 0 northbridge-sql chown -R mssql /var/opt/mssql/data/import
   On Docker, replace every C:\NorthbridgeData\ below with
   /var/opt/mssql/data/import/ and remove the CODEPAGE line.
   This script changes no base table: it creates dbo.Stage_* tables only. */

-- 1. Files, staging tables and where to put the files
-- Remove an earlier copy so the script can run again
-- (DROP TABLE IF EXISTS: chapter 22 explains this in full).
DROP TABLE IF EXISTS dbo.Stage_Payment;

SELECT *
INTO dbo.Stage_Payment          -- the new, empty staging table
FROM dbo.Payment
WHERE 1 = 0;                    -- a condition that is never true

SELECT COUNT(*) AS RowsInStage
FROM dbo.Stage_Payment;
GO

-- 2. BULK INSERT: loading a CSV file into a table
BULK INSERT dbo.Stage_Payment
FROM 'C:\NorthbridgeData\Payment.csv'
WITH (
    FIRSTROW = 2,             -- line 1 is the header row
    FIELDTERMINATOR = ',',    -- fields are separated by commas
    ROWTERMINATOR = '\n'      -- each line ends with CR + LF
);

SELECT
    COUNT(*)        AS RowsLoaded,
    COUNT(PaidDate) AS RowsWithPaidDate,
    SUM(AmountDue)  AS TotalDue,
    SUM(AmountPaid) AS TotalPaid
FROM dbo.Stage_Payment;
GO

-- 3. Quoted fields: FORMAT = 'CSV', and CODEPAGE
DROP TABLE IF EXISTS dbo.Stage_Collateral;

SELECT *
INTO dbo.Stage_Collateral
FROM dbo.Collateral
WHERE 1 = 0;

BULK INSERT dbo.Stage_Collateral
FROM 'C:\NorthbridgeData\Collateral.csv'
WITH (
    FORMAT = 'CSV',           -- understand "quoted, values"
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    CODEPAGE = '65001'        -- the file is UTF-8 (Windows only)
);

SELECT TOP (5)
    CollateralID,
    LoanID,
    CollateralType,
    Description
FROM dbo.Stage_Collateral
ORDER BY CollateralID;
GO

-- 4. When rows fail: MAXERRORS, ERRORFILE and the error messages
-- Delete C:\NorthbridgeData\Collateral_rejected.txt and
-- Collateral_rejected.txt.Error.Txt before running this again.
DROP TABLE IF EXISTS dbo.Stage_Collateral;

SELECT *
INTO dbo.Stage_Collateral
FROM dbo.Collateral
WHERE 1 = 0;

BULK INSERT dbo.Stage_Collateral
FROM 'C:\NorthbridgeData\Collateral.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    MAXERRORS = 1000,      -- do not stop after 10 rejected rows
    ERRORFILE = 'C:\NorthbridgeData\Collateral_rejected.txt'
);

SELECT
    COUNT(*)                    AS RowsLoaded,
    COUNT(DISTINCT Description) AS DistinctDescriptions
FROM dbo.Stage_Collateral;
GO

-- Reload Stage_Collateral correctly (statement of section 3).
DROP TABLE IF EXISTS dbo.Stage_Collateral;

SELECT *
INTO dbo.Stage_Collateral
FROM dbo.Collateral
WHERE 1 = 0;

BULK INSERT dbo.Stage_Collateral
FROM 'C:\NorthbridgeData\Collateral.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n'
);
GO

-- 5. OPENROWSET(BULK ...): reading a file without loading it
SELECT
    LEN(f.BulkColumn) AS CharactersInFile,
    LEN(f.BulkColumn)
      - LEN(REPLACE(f.BulkColumn, CHAR(10), '')) AS LinesInFile,
    LEFT(f.BulkColumn, 42) AS StartOfFile
FROM OPENROWSET(
        BULK 'C:\NorthbridgeData\Branch.csv',
        SINGLE_CLOB
     ) AS f;
GO

/* Create the format file in a Command Prompt (one line):
   bcp NorthbridgeLending.dbo.Stage_Payment format nul -c -t, -f C:\NorthbridgeData\Payment.fmt -S localhost -T -u
   Docker:
   docker exec -it northbridge-sql /opt/mssql-tools18/bin/bcp NorthbridgeLending.dbo.Stage_Payment format /dev/null -c -t, -r "\r\n" -f /var/opt/mssql/data/import/Payment.fmt -S localhost -U sa -P "<YourPassword>" -u
*/

SELECT TOP (5)
    CAST(p.PaymentID AS INT)              AS PaymentID,
    CAST(p.LoanID AS INT)                 AS LoanID,
    CAST(p.DueDate AS DATE)               AS DueDate,
    CAST(p.AmountDue AS DECIMAL(12,2))    AS AmountDue,
    CAST(NULLIF(p.PaidDate, '') AS DATE)  AS PaidDate
FROM OPENROWSET(
        BULK 'C:\NorthbridgeData\Payment.csv',
        FORMATFILE = 'C:\NorthbridgeData\Payment.fmt',
        FIRSTROW = 2
     ) AS p
WHERE NULLIF(p.PaidDate, '') IS NULL     -- missed instalments
ORDER BY CAST(p.PaymentID AS INT);
GO

-- 6. bcp: copying data in and out from the command line
/* bcp out (Command Prompt):
   bcp NorthbridgeLending.dbo.Branch out C:\NorthbridgeData\Branch_out.csv -c -t, -S localhost -T -u
   Docker:
   docker exec -it northbridge-sql /opt/mssql-tools18/bin/bcp NorthbridgeLending.dbo.Branch out /var/opt/mssql/data/import/Branch_out.csv -c -t, -S localhost -U sa -P "<YourPassword>" -u
   The file has 396 characters and no header row.
*/

/* bcp queryout:
   bcp "SELECT BranchID, BranchName FROM NorthbridgeLending.dbo.Branch WHERE Region = N'Scotland' ORDER BY BranchID" queryout C:\NorthbridgeData\Branch_Scotland.csv -c -t, -S localhost -T -u
*/

-- bcp in: empty the staging table first.
DROP TABLE IF EXISTS dbo.Stage_Payment;

SELECT *
INTO dbo.Stage_Payment
FROM dbo.Payment
WHERE 1 = 0;
GO

/* Then in the Command Prompt:
   bcp NorthbridgeLending.dbo.Stage_Payment in C:\NorthbridgeData\Payment.csv -c -t, -F 2 -S localhost -T -u
*/
SELECT
    COUNT(*)        AS RowsLoaded,
    COUNT(PaidDate) AS RowsWithPaidDate,
    SUM(AmountDue)  AS TotalDue,
    SUM(AmountPaid) AS TotalPaid
FROM dbo.Stage_Payment;
GO

-- 7. Permissions for bulk operations
SELECT
    IS_SRVROLEMEMBER('sysadmin')  AS IsSysadmin,
    IS_SRVROLEMEMBER('bulkadmin') AS IsBulkadmin;
GO

-- 8. The Excel workbook and the Import Flat File wizard
-- Run after importing LoanOfficer_fromExcel.csv as dbo.Stage_LoanOfficer
-- with the wizard (the IF skips this step when the import has not been done).
IF OBJECT_ID(N'dbo.Stage_LoanOfficer') IS NOT NULL
BEGIN
    SELECT COUNT(*) AS RowsImported
    FROM dbo.Stage_LoanOfficer;

    SELECT TOP (3)
        OfficerID,
        FirstName,
        LastName,
        BranchID
    FROM dbo.Stage_LoanOfficer
    ORDER BY OfficerID;
END;
GO

-- Applied example: load, check and reconcile the payment file
-- Step 1. Prepare an empty staging table.
DROP TABLE IF EXISTS dbo.Stage_Payment;

SELECT *
INTO dbo.Stage_Payment
FROM dbo.Payment
WHERE 1 = 0;
GO

-- Step 2. Count the lines of the file, then load it.
-- Lines in the file, header included.
SELECT
    LEN(f.BulkColumn)
      - LEN(REPLACE(f.BulkColumn, CHAR(10), '')) AS LinesInFile
FROM OPENROWSET(
        BULK 'C:\NorthbridgeData\Payment.csv',
        SINGLE_CLOB
     ) AS f;

BULK INSERT dbo.Stage_Payment
FROM 'C:\NorthbridgeData\Payment.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK                  -- lock the whole table: faster load
);
GO

-- Step 3. Check the content.
SELECT
    COUNT(*)                  AS RowsLoaded,
    COUNT(DISTINCT PaymentID) AS DistinctPaymentIDs,
    SUM(CASE WHEN PaidDate IS NULL THEN 1 ELSE 0 END)
                              AS MissedInstalments,
    SUM(CASE WHEN PaidDate IS NULL AND AmountPaid <> 0
             THEN 1 ELSE 0 END) AS MissedButPaid,
    MIN(DueDate)              AS FirstDue,
    MAX(DueDate)              AS LastDue
FROM dbo.Stage_Payment;
GO

-- Step 4. Check that every payment belongs to a known loan.
SELECT COUNT(*) AS OrphanPayments
FROM dbo.Stage_Payment AS s
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.Loan AS l
    WHERE l.LoanID = s.LoanID
);
GO

-- Step 5. Reconcile the file with the table, row by row.
-- Rows in the file that are not in the table.
SELECT COUNT(*) AS OnlyInFile
FROM (
    SELECT * FROM dbo.Stage_Payment
    EXCEPT
    SELECT * FROM dbo.Payment
) AS d;

-- Rows in the table that are not in the file.
SELECT COUNT(*) AS OnlyInTable
FROM (
    SELECT * FROM dbo.Payment
    EXCEPT
    SELECT * FROM dbo.Stage_Payment
) AS d;
GO

-- Step 6. Report the missed instalments of 2026 by quarter.
SELECT
    DATEPART(QUARTER, DueDate) AS Quarter2026,
    COUNT(*)                   AS InstalmentsDue,
    SUM(CASE WHEN PaidDate IS NULL THEN 1 ELSE 0 END)
                               AS Missed,
    CAST(SUM(CASE WHEN PaidDate IS NULL THEN AmountDue
                  ELSE 0 END) AS DECIMAL(12,2))
                               AS MissedAmount
FROM dbo.Stage_Payment
WHERE DueDate >= '2026-01-01'
  AND DueDate <  '2027-01-01'
GROUP BY DATEPART(QUARTER, DueDate)
ORDER BY Quarter2026;
GO

-- Clean-up: remove the staging tables of this chapter.
-- No base table was changed.
DROP TABLE IF EXISTS dbo.Stage_Payment;
DROP TABLE IF EXISTS dbo.Stage_Collateral;
DROP TABLE IF EXISTS dbo.Stage_LoanOfficer;
GO
