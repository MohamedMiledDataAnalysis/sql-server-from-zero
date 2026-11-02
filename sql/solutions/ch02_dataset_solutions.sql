/* SQL Server from Zero — Volume 1
   Chapter 02: The Northbridge Lending database
   Target: SQL Server 2025 (runs on 2022). */

-- ===== Correction 02.1 =====
-- Run sql/setup/01, 02 and 03 in this order, with F5 in each window.
-- Then, in a new query window:
SELECT DB_NAME() AS CurrentDatabase;  -- which database is this window in?

-- ===== Correction 02.2 =====
USE NorthbridgeLending;   -- work inside the bank's database
GO

SELECT *                  -- every column
FROM dbo.Product          -- the product catalogue
ORDER BY ProductCode;     -- alphabetical order of the code

-- ===== Correction 02.3 =====
USE master;                              -- deliberately stay outside
GO

SELECT TOP (5) *                         -- five rows, every column
FROM NorthbridgeLending.dbo.Branch       -- three-part name
ORDER BY BranchID;                       -- branches 1 to 5

-- ===== Correction 02.4 =====
USE NorthbridgeLending;
GO

SELECT ORDINAL_POSITION,              -- creation order
       COLUMN_NAME,                   -- name of the column
       DATA_TYPE,                     -- its type
       IS_NULLABLE                    -- YES if NULL is allowed
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Payment'          -- only the Payment table
ORDER BY ORDINAL_POSITION;

-- ===== Correction 02.5 =====
SELECT TABLE_NAME,                    -- which table
       COLUMN_NAME                    -- which column
FROM INFORMATION_SCHEMA.COLUMNS
WHERE IS_NULLABLE = 'YES'             -- only columns that accept NULL
ORDER BY TABLE_NAME, COLUMN_NAME;

-- ===== Correction 02.6 =====
EXEC sp_help 'dbo.Payment';   -- describe the Payment table

-- ===== Correction 02.7 =====
SELECT TOP (3) RatingDate,             -- three most recent
       CreditScore,
       Grade,
       ProbabilityOfDefault
FROM dbo.CreditRating
WHERE CustomerID = 208                 -- Grace Clarke
ORDER BY RatingDate DESC;              -- newest first

-- ===== Correction 02.8 =====
SELECT name AS ForeignKeyName,
       OBJECT_NAME(parent_object_id) AS ChildTable
FROM sys.foreign_keys
WHERE OBJECT_NAME(referenced_object_id) = 'Branch'   -- parent is Branch
ORDER BY ChildTable;

