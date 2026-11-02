/* SQL Server from Zero — Volume 1
   Chapter 15: Loading files: BULK INSERT, OPENROWSET and bcp
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

/* Files: C:\NorthbridgeData\ on Windows, /var/opt/mssql/data/import/
   inside the Docker container (copied with docker cp, chapter 15 section 1).
   On Docker, replace every C:\NorthbridgeData\ with /var/opt/mssql/data/import/.
   Corrections 15.6 and 15.8 need Payment.fmt (section 5).
   No base table is changed: the exercises create dbo.Stage_* and
   dbo.Practice_* tables, dropped by the clean-up block at the end. */

-- Correction 15.1
DROP TABLE IF EXISTS dbo.Stage_Branch;   -- allow re-running

SELECT *
INTO dbo.Stage_Branch                    -- same columns as Branch
FROM dbo.Branch
WHERE 1 = 0;                             -- structure only, no rows

BULK INSERT dbo.Stage_Branch
FROM 'C:\NorthbridgeData\Branch.csv'     -- Docker: /var/opt/...
WITH (
    FIRSTROW = 2,                        -- skip the header row
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n'                 -- CR + LF
);

SELECT TOP (3)
    BranchID,
    BranchName,
    City
FROM dbo.Stage_Branch
ORDER BY BranchID;
GO

-- Correction 15.2
SELECT
    LEN(f.BulkColumn) AS CharactersInFile,  -- whole file
    LEN(f.BulkColumn)
      - LEN(REPLACE(f.BulkColumn, CHAR(10), ''))
                      AS LinesInFile        -- one LF per line
FROM OPENROWSET(
        BULK 'C:\NorthbridgeData\Product.csv',
        SINGLE_CLOB                         -- one VARCHAR(MAX)
     ) AS f;                                -- alias is required
GO

-- Correction 15.3
/* Command Prompt (one line):
   bcp "SELECT * FROM NorthbridgeLending.dbo.Product ORDER BY ProductCode" queryout C:\NorthbridgeData\Product_out.csv -c -t, -S localhost -T -u
   Docker:
   docker exec -it northbridge-sql /opt/mssql-tools18/bin/bcp "SELECT * FROM NorthbridgeLending.dbo.Product ORDER BY ProductCode" queryout /var/opt/mssql/data/import/Product_out.csv -c -t, -S localhost -U sa -P "<YourPassword>" -u
*/
SELECT
    LEN(f.BulkColumn) AS CharactersInFile,
    REPLACE(LEFT(f.BulkColumn,
                 CHARINDEX(CHAR(10), f.BulkColumn) - 1),
            CHAR(13), '') AS FirstLine
         -- everything before the first line feed, without the
         -- carriage return that Windows adds
FROM OPENROWSET(
        BULK 'C:\NorthbridgeData\Product_out.csv',
        SINGLE_CLOB
     ) AS f;
GO

-- Correction 15.4
DROP TABLE IF EXISTS dbo.Stage_Collateral;

SELECT *
INTO dbo.Stage_Collateral
FROM dbo.Collateral
WHERE 1 = 0;

BULK INSERT dbo.Stage_Collateral
FROM 'C:\NorthbridgeData\Collateral.csv'
WITH (
    FORMAT = 'CSV',            -- quoted fields keep their commas
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n'
);                             -- no CODEPAGE: valid on Docker too

SELECT
    CollateralType,
    COUNT(*) AS Items
FROM dbo.Stage_Collateral
GROUP BY CollateralType
ORDER BY Items DESC;
GO

-- Correction 15.5
DROP TABLE IF EXISTS dbo.Stage_CreditRating;

SELECT *
INTO dbo.Stage_CreditRating
FROM dbo.CreditRating
WHERE 1 = 0;

BULK INSERT dbo.Stage_CreditRating
FROM 'C:\NorthbridgeData\CreditRating.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n'
);

SELECT
    (SELECT COUNT(*) FROM dbo.Stage_CreditRating) AS RowsLoaded,
    (SELECT COUNT(*)
     FROM (SELECT * FROM dbo.Stage_CreditRating
           EXCEPT
           SELECT * FROM dbo.CreditRating) AS a)   AS OnlyInFile,
    (SELECT COUNT(*)
     FROM (SELECT * FROM dbo.CreditRating
           EXCEPT
           SELECT * FROM dbo.Stage_CreditRating) AS b) AS OnlyInTable;
GO

-- Correction 15.6
SELECT
    YEAR(CAST(p.DueDate AS DATE)) AS DueYear,   -- text -> DATE
    COUNT(*)                      AS Missed
FROM OPENROWSET(
        BULK 'C:\NorthbridgeData\Payment.csv',
        FORMATFILE = 'C:\NorthbridgeData\Payment.fmt',
        FIRSTROW = 2                            -- skip the header
     ) AS p
WHERE NULLIF(p.PaidDate, '') IS NULL            -- missed only
GROUP BY YEAR(CAST(p.DueDate AS DATE))
ORDER BY DueYear;
GO

-- Correction 15.7
DROP TABLE IF EXISTS dbo.Stage_CustomerBad;

SELECT
    CustomerID, FirstName, LastName, DateOfBirth, Email,
    CAST(NULL AS INT) AS Phone,     -- the colleague's mistake
    City, Postcode, EmploymentStatus, AnnualIncome,
    CreditScore, JoinedDate, HomeBranchID
INTO dbo.Stage_CustomerBad
FROM dbo.Customer
WHERE 1 = 0;                        -- structure only

-- Delete Customer_rejected.txt and its .Error.Txt file first
-- if they exist from an earlier run.
BULK INSERT dbo.Stage_CustomerBad
FROM 'C:\NorthbridgeData\Customer.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    MAXERRORS = 500,                -- keep going past 10 errors
    ERRORFILE = 'C:\NorthbridgeData\Customer_rejected.txt'
);

SELECT TOP (5)
    CustomerID,
    FirstName,
    LastName,
    City
FROM dbo.Stage_CustomerBad
ORDER BY CustomerID;
GO

-- Correction 15.8
DROP TABLE IF EXISTS dbo.Practice_Payment2026;

SELECT *
INTO dbo.Practice_Payment2026
FROM dbo.Payment
WHERE 1 = 0;

INSERT INTO dbo.Practice_Payment2026
    (PaymentID, LoanID, InstalmentNumber, DueDate,
     AmountDue, PaidDate, AmountPaid, DaysLate)
SELECT
    CAST(p.PaymentID AS INT),
    CAST(p.LoanID AS INT),
    CAST(p.InstalmentNumber AS SMALLINT),
    CAST(p.DueDate AS DATE),
    CAST(p.AmountDue AS DECIMAL(12,2)),
    CAST(NULLIF(p.PaidDate, '') AS DATE),       -- empty -> NULL
    CAST(p.AmountPaid AS DECIMAL(12,2)),
    CAST(NULLIF(p.DaysLate, '') AS SMALLINT)    -- empty -> NULL
FROM OPENROWSET(
        BULK 'C:\NorthbridgeData\Payment.csv',
        FORMATFILE = 'C:\NorthbridgeData\Payment.fmt',
        FIRSTROW = 2
     ) AS p
WHERE CAST(p.DueDate AS DATE) >= '2026-01-01'   -- 2026 only
  AND CAST(p.DueDate AS DATE) <  '2027-01-01';

SELECT
    COUNT(*)                   AS RowsLoaded,
    COUNT(*) - COUNT(PaidDate) AS Missed,
    SUM(AmountDue)             AS TotalDue,
    SUM(AmountPaid)            AS TotalPaid
FROM dbo.Practice_Payment2026;
GO

-- Clean-up: remove every table the exercises created.
-- The base tables were not changed.
DROP TABLE IF EXISTS dbo.Stage_Branch;
DROP TABLE IF EXISTS dbo.Stage_Collateral;
DROP TABLE IF EXISTS dbo.Stage_CreditRating;
DROP TABLE IF EXISTS dbo.Stage_CustomerBad;
DROP TABLE IF EXISTS dbo.Practice_Payment2026;
GO
