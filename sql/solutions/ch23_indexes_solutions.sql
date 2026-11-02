/* SQL Server from Zero — Volume 1
   Chapter 23: Indexes and statistics
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Works on its own: create the schema if the chapter script has not been run.
IF SCHEMA_ID(N'risk') IS NULL
    EXEC (N'CREATE SCHEMA risk AUTHORIZATION dbo;');
GO

-- The corrections use the copies made in section 1 of the chapter.
IF OBJECT_ID(N'risk.PaymentCopy') IS NULL
    SELECT * INTO risk.PaymentCopy FROM dbo.Payment;
IF OBJECT_ID(N'risk.LoanCopy') IS NULL
    SELECT * INTO risk.LoanCopy FROM dbo.Loan;
GO

-- ------------------------------------------------------------------
-- Correction 23.1
-- ------------------------------------------------------------------
SELECT index_id, name, type_desc, is_unique
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'dbo.Loan')
ORDER BY index_id;
GO


-- ------------------------------------------------------------------
-- Correction 23.2
-- ------------------------------------------------------------------
CREATE INDEX IX_PaymentCopy_DueDate
ON risk.PaymentCopy (DueDate);

SELECT COUNT(*) AS DueOn1Sep
FROM risk.PaymentCopy
WHERE DueDate = '2026-09-01';
GO


-- ------------------------------------------------------------------
-- Correction 23.3
-- ------------------------------------------------------------------
CREATE INDEX IX_PaymentCopy_Loan_Due
ON risk.PaymentCopy (LoanID, DueDate);

SELECT COUNT(*) AS a FROM risk.PaymentCopy
WHERE LoanID = 10041;                              -- seek: leading column

SELECT COUNT(*) AS b FROM risk.PaymentCopy
WHERE LoanID = 10041 AND DueDate >= '2026-01-01';  -- seek: both columns

SELECT COUNT(*) AS c FROM risk.PaymentCopy
WHERE DueDate = '2026-09-01';                      -- no seek on this one
GO


-- ------------------------------------------------------------------
-- Correction 23.4
-- ------------------------------------------------------------------
INSERT INTO risk.PaymentCopy
    (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
     PaidDate, AmountPaid, DaysLate)
VALUES (99002, 10041, 36, '2026-10-01', 2674.00, NULL, 0.00, NULL);

-- Refused with error 2601; uncomment to see it:
-- INSERT INTO risk.PaymentCopy
--     (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
--      PaidDate, AmountPaid, DaysLate)
-- VALUES (99003, 10041, 36, '2026-10-01', 2674.00, NULL, 0.00, NULL);

DELETE FROM risk.PaymentCopy
WHERE PaymentID = 99002;                  -- restore the copy
GO


-- ------------------------------------------------------------------
-- Correction 23.5
-- ------------------------------------------------------------------
INSERT INTO risk.CustomerContact (CustomerID, Email)
VALUES (9001, NULL);                      -- outside the filter

INSERT INTO risk.CustomerContact (CustomerID, Email)
VALUES (9002, NULL);                      -- outside the filter too

-- Refused with error 2601; uncomment to see it:
-- INSERT INTO risk.CustomerContact (CustomerID, Email)
-- SELECT 9003, Email
-- FROM risk.CustomerContact
-- WHERE CustomerID = 1;                     -- copies customer 1's email
GO


-- ------------------------------------------------------------------
-- Correction 23.6
-- ------------------------------------------------------------------
CREATE INDEX IX_PaymentCopy_DueDate_Paid
ON risk.PaymentCopy (DueDate)
INCLUDE (LoanID, AmountPaid);             -- covers the query

SELECT TOP (5)
       LoanID,
       SUM(AmountPaid) AS Paid2026
FROM risk.PaymentCopy
WHERE DueDate >= '2026-01-01'             -- sargable range,
  AND DueDate <  '2027-01-01'             -- not YEAR(DueDate) = 2026
GROUP BY LoanID
ORDER BY Paid2026 DESC, LoanID;
GO


-- ------------------------------------------------------------------
-- Correction 23.7
-- ------------------------------------------------------------------
ALTER INDEX PK_LoanCopy ON risk.LoanCopy DISABLE;
GO

-- Deliberate error; uncomment to see it:
-- SELECT COUNT(*) FROM risk.LoanCopy;       -- fails: error 8655
GO

ALTER INDEX PK_LoanCopy ON risk.LoanCopy REBUILD;
ALTER INDEX IX_LoanCopy_BranchID ON risk.LoanCopy REBUILD;

SELECT name, type_desc, is_disabled
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'risk.LoanCopy')
ORDER BY name;
GO


-- ------------------------------------------------------------------
-- Correction 23.8
-- ------------------------------------------------------------------
CREATE STATISTICS ST_LoanCopy_Branch_Product
ON risk.LoanCopy (BranchID, ProductCode)
WITH FULLSCAN;

DBCC SHOW_STATISTICS (N'risk.LoanCopy', ST_LoanCopy_Branch_Product)
WITH DENSITY_VECTOR;

-- Check the density from the data.
SELECT COUNT(DISTINCT BranchID) AS Branches,
       COUNT(*) AS BranchProductPairs
FROM (SELECT DISTINCT BranchID, ProductCode
      FROM risk.LoanCopy) AS pairs;
GO

