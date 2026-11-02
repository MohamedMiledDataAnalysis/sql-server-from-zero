/* SQL Server from Zero — Volume 1
   Chapter 28: Partitioning — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Correction 28.1
-- ==============================================================

-- Exercise setup: rebuild the partitioned practice table
DROP TABLE IF EXISTS dbo.Practice_PaymentByYear;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
DROP TABLE IF EXISTS dbo.Practice_Payment2025;
DROP TABLE IF EXISTS dbo.Practice_Payment2026;
DROP TABLE IF EXISTS dbo.Practice_PaymentBad;
GO
IF EXISTS (SELECT 1 FROM sys.partition_schemes
           WHERE name = N'psPaymentYear')
    DROP PARTITION SCHEME psPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions
           WHERE name = N'pfPaymentYear')
    DROP PARTITION FUNCTION pfPaymentYear;
GO
CREATE PARTITION FUNCTION pfPaymentYear (DATE)
AS RANGE RIGHT
FOR VALUES ('2022-01-01', '2023-01-01', '2024-01-01',
            '2025-01-01', '2026-01-01');
GO
CREATE PARTITION SCHEME psPaymentYear
AS PARTITION pfPaymentYear
ALL TO ([PRIMARY]);
GO
CREATE TABLE dbo.Practice_PaymentByYear (
    PaymentID        INT            NOT NULL,
    LoanID           INT            NOT NULL,
    InstalmentNumber SMALLINT       NOT NULL,
    DueDate          DATE           NOT NULL,
    AmountDue        DECIMAL(12,2)  NOT NULL,
    PaidDate         DATE           NULL,
    AmountPaid       DECIMAL(12,2)  NOT NULL,
    DaysLate         SMALLINT       NULL,
    CONSTRAINT PK_Practice_PaymentByYear
        PRIMARY KEY CLUSTERED (DueDate, PaymentID)
) ON psPaymentYear (DueDate);
GO
INSERT INTO dbo.Practice_PaymentByYear
    (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
     PaidDate, AmountPaid, DaysLate)
SELECT PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
       PaidDate, AmountPaid, DaysLate
FROM dbo.Payment;

CREATE NONCLUSTERED INDEX IX_Practice_PaymentByYear_LoanID
    ON dbo.Practice_PaymentByYear (LoanID);
GO
SELECT $PARTITION.pfPaymentYear('2021-06-30') AS Jun2021,
       $PARTITION.pfPaymentYear('2022-01-01') AS Jan2022,  -- boundary
       $PARTITION.pfPaymentYear('2025-12-31') AS Dec2025,
       $PARTITION.pfPaymentYear('2030-01-01') AS Jan2030;  -- open end
GO

-- ==============================================================
-- Correction 28.2
-- ==============================================================

CREATE PARTITION FUNCTION pfLoanOriginLeft (DATE)
AS RANGE LEFT                              -- boundary closes a range
FOR VALUES ('2022-12-31', '2023-12-31', '2024-12-31', '2025-12-31');
GO

SELECT $PARTITION.pfLoanOriginLeft('2023-12-31') AS Dec2023,
       $PARTITION.pfLoanOriginLeft('2024-01-01') AS Jan2024;
GO

DROP PARTITION FUNCTION pfLoanOriginLeft;
GO

-- ==============================================================
-- Correction 28.3
-- ==============================================================

-- Exercise setup: rebuild the partitioned practice table
DROP TABLE IF EXISTS dbo.Practice_PaymentByYear;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
DROP TABLE IF EXISTS dbo.Practice_Payment2025;
DROP TABLE IF EXISTS dbo.Practice_Payment2026;
DROP TABLE IF EXISTS dbo.Practice_PaymentBad;
GO
IF EXISTS (SELECT 1 FROM sys.partition_schemes
           WHERE name = N'psPaymentYear')
    DROP PARTITION SCHEME psPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions
           WHERE name = N'pfPaymentYear')
    DROP PARTITION FUNCTION pfPaymentYear;
GO
CREATE PARTITION FUNCTION pfPaymentYear (DATE)
AS RANGE RIGHT
FOR VALUES ('2022-01-01', '2023-01-01', '2024-01-01',
            '2025-01-01', '2026-01-01');
GO
CREATE PARTITION SCHEME psPaymentYear
AS PARTITION pfPaymentYear
ALL TO ([PRIMARY]);
GO
CREATE TABLE dbo.Practice_PaymentByYear (
    PaymentID        INT            NOT NULL,
    LoanID           INT            NOT NULL,
    InstalmentNumber SMALLINT       NOT NULL,
    DueDate          DATE           NOT NULL,
    AmountDue        DECIMAL(12,2)  NOT NULL,
    PaidDate         DATE           NULL,
    AmountPaid       DECIMAL(12,2)  NOT NULL,
    DaysLate         SMALLINT       NULL,
    CONSTRAINT PK_Practice_PaymentByYear
        PRIMARY KEY CLUSTERED (DueDate, PaymentID)
) ON psPaymentYear (DueDate);
GO
INSERT INTO dbo.Practice_PaymentByYear
    (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
     PaidDate, AmountPaid, DaysLate)
SELECT PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
       PaidDate, AmountPaid, DaysLate
FROM dbo.Payment;

CREATE NONCLUSTERED INDEX IX_Practice_PaymentByYear_LoanID
    ON dbo.Practice_PaymentByYear (LoanID);
GO
SELECT p.partition_number AS PartitionNumber,
       p.rows             AS RowsInPartition
FROM sys.partitions AS p
INNER JOIN sys.indexes AS i
    ON i.object_id = p.object_id
   AND i.index_id = p.index_id          -- same index
WHERE i.name = N'IX_Practice_PaymentByYear_LoanID'
ORDER BY p.partition_number;
GO

-- ==============================================================
-- Correction 28.4
-- ==============================================================

-- Exercise setup: rebuild the partitioned practice table
DROP TABLE IF EXISTS dbo.Practice_PaymentByYear;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
DROP TABLE IF EXISTS dbo.Practice_Payment2025;
DROP TABLE IF EXISTS dbo.Practice_Payment2026;
DROP TABLE IF EXISTS dbo.Practice_PaymentBad;
GO
IF EXISTS (SELECT 1 FROM sys.partition_schemes
           WHERE name = N'psPaymentYear')
    DROP PARTITION SCHEME psPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions
           WHERE name = N'pfPaymentYear')
    DROP PARTITION FUNCTION pfPaymentYear;
GO
CREATE PARTITION FUNCTION pfPaymentYear (DATE)
AS RANGE RIGHT
FOR VALUES ('2022-01-01', '2023-01-01', '2024-01-01',
            '2025-01-01', '2026-01-01');
GO
CREATE PARTITION SCHEME psPaymentYear
AS PARTITION pfPaymentYear
ALL TO ([PRIMARY]);
GO
CREATE TABLE dbo.Practice_PaymentByYear (
    PaymentID        INT            NOT NULL,
    LoanID           INT            NOT NULL,
    InstalmentNumber SMALLINT       NOT NULL,
    DueDate          DATE           NOT NULL,
    AmountDue        DECIMAL(12,2)  NOT NULL,
    PaidDate         DATE           NULL,
    AmountPaid       DECIMAL(12,2)  NOT NULL,
    DaysLate         SMALLINT       NULL,
    CONSTRAINT PK_Practice_PaymentByYear
        PRIMARY KEY CLUSTERED (DueDate, PaymentID)
) ON psPaymentYear (DueDate);
GO
INSERT INTO dbo.Practice_PaymentByYear
    (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
     PaidDate, AmountPaid, DaysLate)
SELECT PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
       PaidDate, AmountPaid, DaysLate
FROM dbo.Payment;

CREATE NONCLUSTERED INDEX IX_Practice_PaymentByYear_LoanID
    ON dbo.Practice_PaymentByYear (LoanID);
GO
SELECT $PARTITION.pfPaymentYear(DueDate) AS PartitionNumber,
       COUNT(*)                          AS MissedPayments
FROM dbo.Practice_PaymentByYear
WHERE PaidDate IS NULL                   -- missed instalments
GROUP BY $PARTITION.pfPaymentYear(DueDate)
ORDER BY PartitionNumber;
GO

-- ==============================================================
-- Correction 28.5
-- ==============================================================

-- Exercise setup: rebuild the partitioned practice table
DROP TABLE IF EXISTS dbo.Practice_PaymentByYear;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
DROP TABLE IF EXISTS dbo.Practice_Payment2025;
DROP TABLE IF EXISTS dbo.Practice_Payment2026;
DROP TABLE IF EXISTS dbo.Practice_PaymentBad;
GO
IF EXISTS (SELECT 1 FROM sys.partition_schemes
           WHERE name = N'psPaymentYear')
    DROP PARTITION SCHEME psPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions
           WHERE name = N'pfPaymentYear')
    DROP PARTITION FUNCTION pfPaymentYear;
GO
CREATE PARTITION FUNCTION pfPaymentYear (DATE)
AS RANGE RIGHT
FOR VALUES ('2022-01-01', '2023-01-01', '2024-01-01',
            '2025-01-01', '2026-01-01');
GO
CREATE PARTITION SCHEME psPaymentYear
AS PARTITION pfPaymentYear
ALL TO ([PRIMARY]);
GO
CREATE TABLE dbo.Practice_PaymentByYear (
    PaymentID        INT            NOT NULL,
    LoanID           INT            NOT NULL,
    InstalmentNumber SMALLINT       NOT NULL,
    DueDate          DATE           NOT NULL,
    AmountDue        DECIMAL(12,2)  NOT NULL,
    PaidDate         DATE           NULL,
    AmountPaid       DECIMAL(12,2)  NOT NULL,
    DaysLate         SMALLINT       NULL,
    CONSTRAINT PK_Practice_PaymentByYear
        PRIMARY KEY CLUSTERED (DueDate, PaymentID)
) ON psPaymentYear (DueDate);
GO
INSERT INTO dbo.Practice_PaymentByYear
    (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
     PaidDate, AmountPaid, DaysLate)
SELECT PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
       PaidDate, AmountPaid, DaysLate
FROM dbo.Payment;

CREATE NONCLUSTERED INDEX IX_Practice_PaymentByYear_LoanID
    ON dbo.Practice_PaymentByYear (LoanID);
GO
-- Exercise 28.5: the statement as given fails on purpose with Msg 1908
-- (DueDate, the partitioning column, is not in the unique clustered key).
-- CREATE TABLE dbo.Practice_PaymentBad (
--     PaymentID INT  NOT NULL
--         CONSTRAINT PK_Practice_PaymentBad PRIMARY KEY CLUSTERED,
--     LoanID    INT  NOT NULL,
--     DueDate   DATE NOT NULL
-- ) ON psPaymentYear (DueDate);

-- The corrected table.
CREATE TABLE dbo.Practice_PaymentBad (
    PaymentID INT  NOT NULL,
    LoanID    INT  NOT NULL,
    DueDate   DATE NOT NULL,
    CONSTRAINT PK_Practice_PaymentBad
        PRIMARY KEY CLUSTERED (PaymentID, DueDate)  -- DueDate added
) ON psPaymentYear (DueDate);
GO

SELECT i.name, ds.name AS DataSpace, ds.type_desc
FROM sys.indexes AS i
INNER JOIN sys.data_spaces AS ds
    ON ds.data_space_id = i.data_space_id
WHERE i.object_id = OBJECT_ID(N'dbo.Practice_PaymentBad');
GO

DROP TABLE dbo.Practice_PaymentBad;
GO

-- ==============================================================
-- Correction 28.6
-- ==============================================================

-- Exercise setup: rebuild the partitioned practice table
DROP TABLE IF EXISTS dbo.Practice_PaymentByYear;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
DROP TABLE IF EXISTS dbo.Practice_Payment2025;
DROP TABLE IF EXISTS dbo.Practice_Payment2026;
DROP TABLE IF EXISTS dbo.Practice_PaymentBad;
GO
IF EXISTS (SELECT 1 FROM sys.partition_schemes
           WHERE name = N'psPaymentYear')
    DROP PARTITION SCHEME psPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions
           WHERE name = N'pfPaymentYear')
    DROP PARTITION FUNCTION pfPaymentYear;
GO
CREATE PARTITION FUNCTION pfPaymentYear (DATE)
AS RANGE RIGHT
FOR VALUES ('2022-01-01', '2023-01-01', '2024-01-01',
            '2025-01-01', '2026-01-01');
GO
CREATE PARTITION SCHEME psPaymentYear
AS PARTITION pfPaymentYear
ALL TO ([PRIMARY]);
GO
CREATE TABLE dbo.Practice_PaymentByYear (
    PaymentID        INT            NOT NULL,
    LoanID           INT            NOT NULL,
    InstalmentNumber SMALLINT       NOT NULL,
    DueDate          DATE           NOT NULL,
    AmountDue        DECIMAL(12,2)  NOT NULL,
    PaidDate         DATE           NULL,
    AmountPaid       DECIMAL(12,2)  NOT NULL,
    DaysLate         SMALLINT       NULL,
    CONSTRAINT PK_Practice_PaymentByYear
        PRIMARY KEY CLUSTERED (DueDate, PaymentID)
) ON psPaymentYear (DueDate);
GO
INSERT INTO dbo.Practice_PaymentByYear
    (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
     PaidDate, AmountPaid, DaysLate)
SELECT PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
       PaidDate, AmountPaid, DaysLate
FROM dbo.Payment;

CREATE NONCLUSTERED INDEX IX_Practice_PaymentByYear_LoanID
    ON dbo.Practice_PaymentByYear (LoanID);
GO
TRUNCATE TABLE dbo.Practice_PaymentByYear
WITH (PARTITIONS (1 TO 2));              -- 2021 and 2022

SELECT COUNT(*) AS RowsLeft
FROM dbo.Practice_PaymentByYear;
GO

-- ==============================================================
-- Correction 28.7
-- ==============================================================

-- Exercise setup: rebuild the partitioned practice table
DROP TABLE IF EXISTS dbo.Practice_PaymentByYear;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
DROP TABLE IF EXISTS dbo.Practice_Payment2025;
DROP TABLE IF EXISTS dbo.Practice_Payment2026;
DROP TABLE IF EXISTS dbo.Practice_PaymentBad;
GO
IF EXISTS (SELECT 1 FROM sys.partition_schemes
           WHERE name = N'psPaymentYear')
    DROP PARTITION SCHEME psPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions
           WHERE name = N'pfPaymentYear')
    DROP PARTITION FUNCTION pfPaymentYear;
GO
CREATE PARTITION FUNCTION pfPaymentYear (DATE)
AS RANGE RIGHT
FOR VALUES ('2022-01-01', '2023-01-01', '2024-01-01',
            '2025-01-01', '2026-01-01');
GO
CREATE PARTITION SCHEME psPaymentYear
AS PARTITION pfPaymentYear
ALL TO ([PRIMARY]);
GO
CREATE TABLE dbo.Practice_PaymentByYear (
    PaymentID        INT            NOT NULL,
    LoanID           INT            NOT NULL,
    InstalmentNumber SMALLINT       NOT NULL,
    DueDate          DATE           NOT NULL,
    AmountDue        DECIMAL(12,2)  NOT NULL,
    PaidDate         DATE           NULL,
    AmountPaid       DECIMAL(12,2)  NOT NULL,
    DaysLate         SMALLINT       NULL,
    CONSTRAINT PK_Practice_PaymentByYear
        PRIMARY KEY CLUSTERED (DueDate, PaymentID)
) ON psPaymentYear (DueDate);
GO
INSERT INTO dbo.Practice_PaymentByYear
    (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
     PaidDate, AmountPaid, DaysLate)
SELECT PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
       PaidDate, AmountPaid, DaysLate
FROM dbo.Payment;

CREATE NONCLUSTERED INDEX IX_Practice_PaymentByYear_LoanID
    ON dbo.Practice_PaymentByYear (LoanID);
GO
CREATE TABLE dbo.Practice_Payment2025 (
    PaymentID        INT            NOT NULL,
    LoanID           INT            NOT NULL,
    InstalmentNumber SMALLINT       NOT NULL,
    DueDate          DATE           NOT NULL,
    AmountDue        DECIMAL(12,2)  NOT NULL,
    PaidDate         DATE           NULL,
    AmountPaid       DECIMAL(12,2)  NOT NULL,
    DaysLate         SMALLINT       NULL,
    CONSTRAINT PK_Practice_Payment2025
        PRIMARY KEY CLUSTERED (DueDate, PaymentID)   -- same key
) ON [PRIMARY];                                     -- same filegroup

CREATE NONCLUSTERED INDEX IX_Practice_Payment2025_LoanID
    ON dbo.Practice_Payment2025 (LoanID);            -- same index

ALTER TABLE dbo.Practice_PaymentByYear
SWITCH PARTITION 5 TO dbo.Practice_Payment2025;

SELECT COUNT(*)         AS Payments,
       SUM(AmountDue)   AS TotalDue,
       SUM(AmountPaid)  AS TotalPaid,
       SUM(CASE WHEN PaidDate IS NULL THEN 1 ELSE 0 END) AS Missed,
       (SELECT COUNT(*) FROM dbo.Practice_PaymentByYear
        WHERE $PARTITION.pfPaymentYear(DueDate) = 5)    AS Partition5
FROM dbo.Practice_Payment2025;
GO

-- ==============================================================
-- Correction 28.8
-- ==============================================================

-- Exercise setup: rebuild the partitioned practice table
DROP TABLE IF EXISTS dbo.Practice_PaymentByYear;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
DROP TABLE IF EXISTS dbo.Practice_Payment2025;
DROP TABLE IF EXISTS dbo.Practice_Payment2026;
DROP TABLE IF EXISTS dbo.Practice_PaymentBad;
GO
IF EXISTS (SELECT 1 FROM sys.partition_schemes
           WHERE name = N'psPaymentYear')
    DROP PARTITION SCHEME psPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions
           WHERE name = N'pfPaymentYear')
    DROP PARTITION FUNCTION pfPaymentYear;
GO
CREATE PARTITION FUNCTION pfPaymentYear (DATE)
AS RANGE RIGHT
FOR VALUES ('2022-01-01', '2023-01-01', '2024-01-01',
            '2025-01-01', '2026-01-01');
GO
CREATE PARTITION SCHEME psPaymentYear
AS PARTITION pfPaymentYear
ALL TO ([PRIMARY]);
GO
CREATE TABLE dbo.Practice_PaymentByYear (
    PaymentID        INT            NOT NULL,
    LoanID           INT            NOT NULL,
    InstalmentNumber SMALLINT       NOT NULL,
    DueDate          DATE           NOT NULL,
    AmountDue        DECIMAL(12,2)  NOT NULL,
    PaidDate         DATE           NULL,
    AmountPaid       DECIMAL(12,2)  NOT NULL,
    DaysLate         SMALLINT       NULL,
    CONSTRAINT PK_Practice_PaymentByYear
        PRIMARY KEY CLUSTERED (DueDate, PaymentID)
) ON psPaymentYear (DueDate);
GO
INSERT INTO dbo.Practice_PaymentByYear
    (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
     PaidDate, AmountPaid, DaysLate)
SELECT PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
       PaidDate, AmountPaid, DaysLate
FROM dbo.Payment;

CREATE NONCLUSTERED INDEX IX_Practice_PaymentByYear_LoanID
    ON dbo.Practice_PaymentByYear (LoanID);
GO
ALTER PARTITION SCHEME psPaymentYear
NEXT USED [PRIMARY];

ALTER PARTITION FUNCTION pfPaymentYear ()
SPLIT RANGE ('2026-07-01');              -- inside a full partition

SELECT p.partition_number      AS PartitionNumber,
       CAST(lo.value AS DATE)  AS FromDate,
       CAST(hi.value AS DATE)  AS ToDate,
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
-- Clean-up: remove every object created by the exercises
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_PaymentByYear;
DROP TABLE IF EXISTS dbo.Practice_Payment2025;
DROP TABLE IF EXISTS dbo.Practice_Payment2026;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
DROP TABLE IF EXISTS dbo.Practice_PaymentBad;
DROP TABLE IF EXISTS dbo.Practice_LoanByYear;
GO
IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'psPaymentYear')
    DROP PARTITION SCHEME psPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'psLoanYear')
    DROP PARTITION SCHEME psLoanYear;
GO
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pfPaymentYear')
    DROP PARTITION FUNCTION pfPaymentYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pfLoanYear')
    DROP PARTITION FUNCTION pfLoanYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pfLoanOriginLeft')
    DROP PARTITION FUNCTION pfLoanOriginLeft;
GO
