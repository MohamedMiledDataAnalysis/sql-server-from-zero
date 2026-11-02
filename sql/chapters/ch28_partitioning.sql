/* SQL Server from Zero — Volume 1
   Chapter 28: Partitioning
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Remove objects left by an earlier run of this script (tables first,
-- then schemes, then functions)
DROP TABLE IF EXISTS dbo.Practice_PaymentByYear;
DROP TABLE IF EXISTS dbo.Practice_Payment2026;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
GO
IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'psPaymentYear')
    DROP PARTITION SCHEME psPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pfPaymentYear')
    DROP PARTITION FUNCTION pfPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pfDemoLeft')
    DROP PARTITION FUNCTION pfDemoLeft;
GO

-- ==============================================================
-- 1. Why partition: the payment history by year
-- ==============================================================

SELECT YEAR(DueDate) AS DueYear,
       COUNT(*)      AS Payments
FROM dbo.Payment
GROUP BY YEAR(DueDate)
ORDER BY DueYear;
GO

-- ==============================================================
-- 2. CREATE PARTITION FUNCTION: RANGE RIGHT and RANGE LEFT
-- ==============================================================

CREATE PARTITION FUNCTION pfPaymentYear (DATE)
AS RANGE RIGHT
FOR VALUES ('2022-01-01', '2023-01-01', '2024-01-01',
            '2025-01-01', '2026-01-01');
GO
-- Test the function with $PARTITION
SELECT $PARTITION.pfPaymentYear('2021-12-31') AS Dec2021,
       $PARTITION.pfPaymentYear('2022-01-01') AS Jan2022,
       $PARTITION.pfPaymentYear('2025-06-30') AS Jun2025,
       $PARTITION.pfPaymentYear('2026-09-30') AS Sep2026,
       $PARTITION.pfPaymentYear('2040-01-01') AS Jan2040;
GO
-- RANGE LEFT with the same boundaries (dropped in section 8)
CREATE PARTITION FUNCTION pfDemoLeft (DATE)
AS RANGE LEFT
FOR VALUES ('2022-01-01', '2023-01-01', '2024-01-01',
            '2025-01-01', '2026-01-01');

SELECT $PARTITION.pfDemoLeft('2021-12-31')   AS Dec2021,
       $PARTITION.pfDemoLeft('2022-01-01')   AS Jan2022,
       $PARTITION.pfDemoLeft('2022-01-02')   AS Jan2022b,
       $PARTITION.pfPaymentYear('2022-01-02') AS RightJan2022b;
GO

-- ==============================================================
-- 3. CREATE PARTITION SCHEME: partitions to filegroups
-- ==============================================================

CREATE PARTITION SCHEME psPaymentYear
AS PARTITION pfPaymentYear
ALL TO ([PRIMARY]);
GO

-- ==============================================================
-- 4. A partitioned table and an aligned index
-- ==============================================================

-- A key without DueDate fails with error 1908 (see exercise 28.5).
-- Correct version, load and aligned nonclustered index
DROP TABLE IF EXISTS dbo.Practice_PaymentByYear;

CREATE TABLE dbo.Practice_PaymentByYear (
    PaymentID        INT            NOT NULL,
    LoanID           INT            NOT NULL,
    InstalmentNumber SMALLINT       NOT NULL,
    DueDate          DATE           NOT NULL,  -- partitioning column
    AmountDue        DECIMAL(12,2)  NOT NULL,
    PaidDate         DATE           NULL,
    AmountPaid       DECIMAL(12,2)  NOT NULL,
    DaysLate         SMALLINT       NULL,
    CONSTRAINT PK_Practice_PaymentByYear
        PRIMARY KEY CLUSTERED (DueDate, PaymentID)
) ON psPaymentYear (DueDate);

INSERT INTO dbo.Practice_PaymentByYear
    (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
     PaidDate, AmountPaid, DaysLate)
SELECT PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
       PaidDate, AmountPaid, DaysLate
FROM dbo.Payment;

CREATE NONCLUSTERED INDEX IX_Practice_PaymentByYear_LoanID
    ON dbo.Practice_PaymentByYear (LoanID);
GO
-- Where the indexes live (described in section 4)
SELECT i.name       AS IndexName,
       i.type_desc  AS IndexType,
       ds.name      AS DataSpace,
       ds.type_desc AS DataSpaceType
FROM sys.indexes AS i
INNER JOIN sys.data_spaces AS ds
    ON ds.data_space_id = i.data_space_id
WHERE i.object_id = OBJECT_ID(N'dbo.Practice_PaymentByYear')
ORDER BY i.index_id;
GO
-- Rows per partition
SELECT partition_number AS PartitionNumber,
       rows             AS RowsInPartition
FROM sys.partitions
WHERE object_id = OBJECT_ID(N'dbo.Practice_PaymentByYear')
  AND index_id = 1                    -- 1 = the clustered index
ORDER BY partition_number;
GO

-- ==============================================================
-- 5. Querying partitions: $PARTITION and partition elimination
-- ==============================================================

SELECT $PARTITION.pfPaymentYear(DueDate) AS PartitionNumber,
       COUNT(*)                          AS Payments,
       MIN(DueDate)                      AS FirstDue,
       MAX(DueDate)                      AS LastDue
FROM dbo.Practice_PaymentByYear
GROUP BY $PARTITION.pfPaymentYear(DueDate)
ORDER BY PartitionNumber;
GO
-- Partition elimination: include the actual execution plan (Ctrl+M)
SELECT COUNT(*)                         AS Payments,
       SUM(AmountDue)                   AS TotalDue,
       SUM(CASE WHEN PaidDate IS NULL THEN 1 ELSE 0 END)
                                        AS Missed
FROM dbo.Practice_PaymentByYear
WHERE DueDate >= '2026-07-01'
  AND DueDate <  '2026-10-01';
GO

-- ==============================================================
-- 6. SPLIT RANGE, MERGE RANGE and NEXT USED
-- ==============================================================

-- Add a boundary for 2027 (empty range: instant)
ALTER PARTITION SCHEME psPaymentYear
NEXT USED [PRIMARY];

ALTER PARTITION FUNCTION pfPaymentYear ()
SPLIT RANGE ('2027-01-01');

SELECT partition_number AS PartitionNumber,
       rows             AS RowsInPartition
FROM sys.partitions
WHERE object_id = OBJECT_ID(N'dbo.Practice_PaymentByYear')
  AND index_id = 1
ORDER BY partition_number;
GO
-- Remove it again
ALTER PARTITION FUNCTION pfPaymentYear ()
MERGE RANGE ('2027-01-01');

SELECT COUNT(*) AS Partitions
FROM sys.partitions
WHERE object_id = OBJECT_ID(N'dbo.Practice_PaymentByYear')
  AND index_id = 1;
GO

-- ==============================================================
-- 7. SWITCH PARTITION and TRUNCATE ... WITH (PARTITIONS)
-- ==============================================================

-- Staging table identical to the partitioned table
DROP TABLE IF EXISTS dbo.Practice_Payment2026;

CREATE TABLE dbo.Practice_Payment2026 (
    PaymentID        INT            NOT NULL,
    LoanID           INT            NOT NULL,
    InstalmentNumber SMALLINT       NOT NULL,
    DueDate          DATE           NOT NULL,
    AmountDue        DECIMAL(12,2)  NOT NULL,
    PaidDate         DATE           NULL,
    AmountPaid       DECIMAL(12,2)  NOT NULL,
    DaysLate         SMALLINT       NULL,
    CONSTRAINT PK_Practice_Payment2026
        PRIMARY KEY CLUSTERED (DueDate, PaymentID)
) ON [PRIMARY];

CREATE NONCLUSTERED INDEX IX_Practice_Payment2026_LoanID
    ON dbo.Practice_Payment2026 (LoanID);
GO
-- Switch out partition 6 (2026)
ALTER TABLE dbo.Practice_PaymentByYear
SWITCH PARTITION 6 TO dbo.Practice_Payment2026;

SELECT (SELECT COUNT(*) FROM dbo.Practice_PaymentByYear
        WHERE $PARTITION.pfPaymentYear(DueDate) = 6) AS Partition6,
       (SELECT COUNT(*) FROM dbo.Practice_Payment2026) AS Staging2026;
GO
-- Expected to fail with error 4982: no CHECK constraint yet (commented out)
-- ALTER TABLE dbo.Practice_Payment2026
-- SWITCH TO dbo.Practice_PaymentByYear PARTITION 6;
GO
-- Add a trusted CHECK constraint, then switch in
ALTER TABLE dbo.Practice_Payment2026
    WITH CHECK                        -- verify existing rows: trusted
    ADD CONSTRAINT CK_Practice_Payment2026_DueDate
        CHECK (DueDate >= '2026-01-01');

ALTER TABLE dbo.Practice_Payment2026
SWITCH TO dbo.Practice_PaymentByYear PARTITION 6;

SELECT (SELECT COUNT(*) FROM dbo.Practice_PaymentByYear
        WHERE $PARTITION.pfPaymentYear(DueDate) = 6) AS Partition6,
       (SELECT COUNT(*) FROM dbo.Practice_Payment2026) AS Staging2026;
GO
-- Empty partition 1 (2021)
TRUNCATE TABLE dbo.Practice_PaymentByYear
WITH (PARTITIONS (1));

SELECT partition_number AS PartitionNumber,
       rows             AS RowsInPartition
FROM sys.partitions
WHERE object_id = OBJECT_ID(N'dbo.Practice_PaymentByYear')
  AND index_id = 1
ORDER BY partition_number;
GO

-- ==============================================================
-- 8. Metadata and removal: functions, boundaries, schemes, DROP
-- ==============================================================

SELECT name, type_desc, fanout, boundary_value_on_right
FROM sys.partition_functions
ORDER BY name;
GO
-- Partitions with their limits and row counts
SELECT p.partition_number      AS PartitionNumber,
       CAST(lo.value AS DATE)  AS FromDate,     -- included
       CAST(hi.value AS DATE)  AS ToDate,       -- excluded
       p.rows                  AS RowsInPartition
FROM sys.partitions AS p
INNER JOIN sys.indexes AS i
    ON i.object_id = p.object_id
   AND i.index_id = p.index_id
INNER JOIN sys.partition_schemes AS ps
    ON ps.data_space_id = i.data_space_id
LEFT JOIN sys.partition_range_values AS lo
    ON lo.function_id = ps.function_id
   AND lo.boundary_id = p.partition_number - 1
LEFT JOIN sys.partition_range_values AS hi
    ON hi.function_id = ps.function_id
   AND hi.boundary_id = p.partition_number
WHERE p.object_id = OBJECT_ID(N'dbo.Practice_PaymentByYear')
  AND p.index_id = 1
ORDER BY p.partition_number;
GO
-- Expected to fail with error 7706: the function is used by a scheme (commented out)
-- DROP PARTITION FUNCTION pfPaymentYear;
GO
-- Drop the unused demo function
IF EXISTS (SELECT 1 FROM sys.partition_functions
           WHERE name = N'pfDemoLeft')
    DROP PARTITION FUNCTION pfDemoLeft;

SELECT name
FROM sys.partition_functions
ORDER BY name;
GO

-- ==============================================================
-- Applied example: the yearly sliding window
-- ==============================================================

-- Step 1. Check the starting point
SELECT p.partition_number      AS PartitionNumber,
       CAST(lo.value AS DATE)  AS FromDate,     -- included
       CAST(hi.value AS DATE)  AS ToDate,       -- excluded
       p.rows                  AS RowsInPartition
FROM sys.partitions AS p
INNER JOIN sys.indexes AS i
    ON i.object_id = p.object_id
   AND i.index_id = p.index_id
INNER JOIN sys.partition_schemes AS ps
    ON ps.data_space_id = i.data_space_id
LEFT JOIN sys.partition_range_values AS lo
    ON lo.function_id = ps.function_id
   AND lo.boundary_id = p.partition_number - 1
LEFT JOIN sys.partition_range_values AS hi
    ON hi.function_id = ps.function_id
   AND hi.boundary_id = p.partition_number
WHERE p.object_id = OBJECT_ID(N'dbo.Practice_PaymentByYear')
  AND p.index_id = 1
ORDER BY p.partition_number;
GO
-- Step 2. Archive table
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;

CREATE TABLE dbo.Practice_PaymentArchive (
    PaymentID        INT            NOT NULL,
    LoanID           INT            NOT NULL,
    InstalmentNumber SMALLINT       NOT NULL,
    DueDate          DATE           NOT NULL,
    AmountDue        DECIMAL(12,2)  NOT NULL,
    PaidDate         DATE           NULL,
    AmountPaid       DECIMAL(12,2)  NOT NULL,
    DaysLate         SMALLINT       NULL,
    CONSTRAINT PK_Practice_PaymentArchive
        PRIMARY KEY CLUSTERED (DueDate, PaymentID)
) ON [PRIMARY];

CREATE NONCLUSTERED INDEX IX_Practice_PaymentArchive_LoanID
    ON dbo.Practice_PaymentArchive (LoanID);
GO
-- Step 3. Switch 2022 out
ALTER TABLE dbo.Practice_PaymentByYear
SWITCH PARTITION 2 TO dbo.Practice_PaymentArchive;

SELECT COUNT(*)       AS ArchivedPayments,
       MIN(DueDate)   AS FirstDue,
       MAX(DueDate)   AS LastDue,
       SUM(AmountDue) AS TotalDue
FROM dbo.Practice_PaymentArchive;
GO
-- Step 4. Merge the empty partitions on the left
ALTER PARTITION FUNCTION pfPaymentYear ()
MERGE RANGE ('2022-01-01');
GO
-- Step 5. Prepare 2027
ALTER PARTITION SCHEME psPaymentYear
NEXT USED [PRIMARY];

ALTER PARTITION FUNCTION pfPaymentYear ()
SPLIT RANGE ('2027-01-01');
GO
-- Step 6. Verify the new window
SELECT p.partition_number      AS PartitionNumber,
       CAST(lo.value AS DATE)  AS FromDate,     -- included
       CAST(hi.value AS DATE)  AS ToDate,       -- excluded
       p.rows                  AS RowsInPartition
FROM sys.partitions AS p
INNER JOIN sys.indexes AS i
    ON i.object_id = p.object_id
   AND i.index_id = p.index_id
INNER JOIN sys.partition_schemes AS ps
    ON ps.data_space_id = i.data_space_id
LEFT JOIN sys.partition_range_values AS lo
    ON lo.function_id = ps.function_id
   AND lo.boundary_id = p.partition_number - 1
LEFT JOIN sys.partition_range_values AS hi
    ON hi.function_id = ps.function_id
   AND hi.boundary_id = p.partition_number
WHERE p.object_id = OBJECT_ID(N'dbo.Practice_PaymentByYear')
  AND p.index_id = 1
ORDER BY p.partition_number;
GO

-- ==============================================================
-- Clean-up: remove every object created in this chapter
-- ==============================================================

-- Tables first, then the scheme, then the functions.
-- The base tables were never changed by this chapter.
DROP TABLE IF EXISTS dbo.Practice_PaymentByYear;
DROP TABLE IF EXISTS dbo.Practice_Payment2026;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
GO
IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'psPaymentYear')
    DROP PARTITION SCHEME psPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pfPaymentYear')
    DROP PARTITION FUNCTION pfPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pfDemoLeft')
    DROP PARTITION FUNCTION pfDemoLeft;
GO
