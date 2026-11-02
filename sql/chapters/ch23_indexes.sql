/* SQL Server from Zero — Volume 1
   Chapter 23: Indexes and statistics
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- ------------------------------------------------------------------
-- Before you start
-- ------------------------------------------------------------------
USE NorthbridgeLending;

IF SCHEMA_ID(N'risk') IS NULL
    EXEC (N'CREATE SCHEMA risk;');

DROP TABLE IF EXISTS risk.PaymentCopy, risk.LoanCopy;

SELECT * INTO risk.PaymentCopy FROM dbo.Payment;
SELECT * INTO risk.LoanCopy FROM dbo.Loan;
GO


-- ------------------------------------------------------------------
-- 1. How SQL Server finds rows
-- ------------------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT PaymentID, InstalmentNumber, DueDate, AmountDue, PaidDate
FROM risk.PaymentCopy
WHERE LoanID = 10041
  AND DueDate >= '2026-07-01'
ORDER BY DueDate;
GO


-- ------------------------------------------------------------------
-- 2. Clustered indexes
-- ------------------------------------------------------------------
SELECT index_id, name, type_desc
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'risk.PaymentCopy');

ALTER TABLE risk.PaymentCopy
ADD CONSTRAINT PK_PaymentCopy PRIMARY KEY CLUSTERED (PaymentID);

SELECT index_id, name, type_desc, is_unique
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'risk.PaymentCopy');
GO

SELECT PaymentID, LoanID, DueDate, AmountDue
FROM risk.PaymentCopy
WHERE PaymentID = 1131;
GO


-- ------------------------------------------------------------------
-- 3. Nonclustered indexes
-- ------------------------------------------------------------------
CREATE INDEX IX_PaymentCopy_LoanID
ON risk.PaymentCopy (LoanID);
GO

CREATE INDEX IX_PaymentCopy_LoanID_DueDate
ON risk.PaymentCopy (LoanID, DueDate)
INCLUDE (InstalmentNumber, AmountDue, PaidDate);
GO


-- ------------------------------------------------------------------
-- 4. Unique and filtered indexes
-- ------------------------------------------------------------------
CREATE UNIQUE INDEX UX_PaymentCopy_Loan_Instalment
ON risk.PaymentCopy (LoanID, InstalmentNumber);

-- Deliberate error 2601 (duplicate (10041, 35)); uncomment to see it:
-- INSERT INTO risk.PaymentCopy
--     (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
--      PaidDate, AmountPaid, DaysLate)
-- VALUES (99001, 10041, 35, '2026-09-01', 2674.00, NULL, 0.00, NULL);
GO

CREATE INDEX IX_PaymentCopy_Missed
ON risk.PaymentCopy (DueDate)
INCLUDE (LoanID, AmountDue, PaidDate)
WHERE PaidDate IS NULL;
GO

DROP TABLE IF EXISTS risk.CustomerContact;

SELECT CustomerID, Email
INTO risk.CustomerContact
FROM dbo.Customer;

CREATE UNIQUE INDEX UX_CustomerContact_Email
ON risk.CustomerContact (Email)
WHERE Email IS NOT NULL;
GO


-- ------------------------------------------------------------------
-- 5. Columnstore indexes
-- ------------------------------------------------------------------
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_PaymentCopy
ON risk.PaymentCopy (LoanID, DueDate, AmountDue, AmountPaid, DaysLate);

SELECT YEAR(DueDate)   AS DueYear,
       COUNT(*)        AS Instalments,
       SUM(AmountDue)  AS TotalDue,
       SUM(AmountPaid) AS TotalPaid
FROM risk.PaymentCopy
GROUP BY YEAR(DueDate)
ORDER BY DueYear;
GO


-- ------------------------------------------------------------------
-- 6. Maintaining, disabling and dropping indexes
-- ------------------------------------------------------------------
SELECT i.name,
       ps.index_type_desc,
       ps.page_count,
       ps.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(
         DB_ID(), OBJECT_ID(N'risk.PaymentCopy'),
         NULL, NULL, 'LIMITED') AS ps
INNER JOIN sys.indexes AS i
    ON i.object_id = ps.object_id
   AND i.index_id = ps.index_id
ORDER BY i.index_id;
GO

ALTER INDEX IX_PaymentCopy_LoanID ON risk.PaymentCopy DISABLE;

SELECT name, is_disabled
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'risk.PaymentCopy')
  AND name = N'IX_PaymentCopy_LoanID';

ALTER INDEX IX_PaymentCopy_LoanID ON risk.PaymentCopy REBUILD;
ALTER INDEX ALL ON risk.PaymentCopy REORGANIZE;
GO

DROP INDEX IF EXISTS IX_PaymentCopy_LoanID ON risk.PaymentCopy;
GO


-- ------------------------------------------------------------------
-- 7. Statistics
-- ------------------------------------------------------------------
CREATE STATISTICS ST_PaymentCopy_LoanID
ON risk.PaymentCopy (LoanID)
WITH FULLSCAN;

DBCC SHOW_STATISTICS (N'risk.PaymentCopy', ST_PaymentCopy_LoanID)
WITH DENSITY_VECTOR;
GO

CREATE STATISTICS ST_PaymentCopy_DaysLate
ON risk.PaymentCopy (DaysLate)
WITH FULLSCAN;

DBCC SHOW_STATISTICS (N'risk.PaymentCopy', ST_PaymentCopy_DaysLate)
WITH HISTOGRAM;
GO

UPDATE STATISTICS risk.PaymentCopy WITH FULLSCAN;
GO


-- ------------------------------------------------------------------
-- Applied example
-- ------------------------------------------------------------------

-- ------------------------------------------------------------------
-- Applied example, Step 1. Write the query and measure it without help.
-- ------------------------------------------------------------------
DROP INDEX IF EXISTS IX_PaymentCopy_Missed ON risk.PaymentCopy;
DROP INDEX IF EXISTS IX_PaymentCopy_LoanID_DueDate ON risk.PaymentCopy;
GO

SET STATISTICS IO ON;

DECLARE @AsOfDate DATE = '2026-09-30';
DECLARE @BranchID INT = 4;

SELECT p.LoanID,
       COUNT(*)         AS MissedRecent,
       SUM(p.AmountDue) AS AmountMissed,
       MIN(p.DueDate)   AS FirstMissed
FROM risk.PaymentCopy AS p
INNER JOIN risk.LoanCopy AS l
    ON l.LoanID = p.LoanID
WHERE l.BranchID = @BranchID
  AND p.PaidDate IS NULL
  AND p.DueDate > DATEADD(DAY, -90, @AsOfDate)
GROUP BY p.LoanID
ORDER BY p.LoanID;
GO


-- ------------------------------------------------------------------
-- Applied example, Step 2. Design the index from the query.
-- ------------------------------------------------------------------

-- ------------------------------------------------------------------
-- Applied example, Step 3. Create the indexes.
-- ------------------------------------------------------------------
CREATE INDEX IX_PaymentCopy_Missed
ON risk.PaymentCopy (DueDate)
INCLUDE (LoanID, AmountDue, PaidDate)
WHERE PaidDate IS NULL;

ALTER TABLE risk.LoanCopy
ADD CONSTRAINT PK_LoanCopy PRIMARY KEY CLUSTERED (LoanID);

CREATE INDEX IX_LoanCopy_BranchID
ON risk.LoanCopy (BranchID);
GO

-- ------------------------------------------------------------------
-- Applied example, Step 4. Measure again.
-- ------------------------------------------------------------------
DECLARE @AsOfDate DATE = '2026-09-30';
DECLARE @BranchID INT = 4;

SELECT p.LoanID,
       COUNT(*)         AS MissedRecent,
       SUM(p.AmountDue) AS AmountMissed,
       MIN(p.DueDate)   AS FirstMissed
FROM risk.PaymentCopy AS p
INNER JOIN risk.LoanCopy AS l
    ON l.LoanID = p.LoanID
WHERE l.BranchID = @BranchID
  AND p.PaidDate IS NULL
  AND p.DueDate > DATEADD(DAY, -90, @AsOfDate)
GROUP BY p.LoanID
ORDER BY p.LoanID;
GO


-- ------------------------------------------------------------------
-- Applied example, Step 5. Check what you built.
-- ------------------------------------------------------------------
SELECT name, type_desc, is_unique, has_filter, filter_definition
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'risk.PaymentCopy')
ORDER BY name;
GO


-- ------------------------------------------------------------------
-- Applied example, Step 6. Serve the whole bank.
-- ------------------------------------------------------------------
DECLARE @AsOfDate DATE = '2026-09-30';

SELECT l.BranchID,
       COUNT(*)         AS MissedRecent,
       SUM(p.AmountDue) AS AmountMissed
FROM risk.PaymentCopy AS p
INNER JOIN risk.LoanCopy AS l
    ON l.LoanID = p.LoanID
WHERE p.PaidDate IS NULL
  AND p.DueDate > DATEADD(DAY, -90, @AsOfDate)
GROUP BY l.BranchID
ORDER BY l.BranchID;
GO


SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- ------------------------------------------------------------------
-- Clean-up (optional). The base tables are never changed by this
-- script; uncomment to remove the practice copies.
-- ------------------------------------------------------------------
-- DROP TABLE IF EXISTS risk.PaymentCopy, risk.LoanCopy,
--     risk.CustomerContact;
-- GO
