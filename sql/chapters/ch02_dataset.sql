/* SQL Server from Zero — Volume 1
   Chapter 02: The Northbridge Lending database
   Target: SQL Server 2025 (runs on 2022). */

-- 2. Building the database
-- The setup statements shown in this section are not repeated here:
-- run sql/setup/01_create_database.sql, 02_create_tables.sql and 03_load_data.sql instead.

-- 3. Working inside the database: USE and the toolbar
USE NorthbridgeLending;
GO

SELECT DB_NAME() AS CurrentDatabase;

-- 5. Keys: how the tables fit together
USE NorthbridgeLending;
GO

SELECT LoanID, CustomerID, ProductCode, BranchID, OfficerID, LoanStatus
FROM dbo.Loan
WHERE LoanID = 10002;

-- 5. Keys: foreign keys
SELECT CustomerID, FirstName, LastName, City, CreditScore
FROM dbo.Customer
WHERE CustomerID = 208;

-- 6. Describing tables with SQL
EXEC sp_help 'dbo.Collateral';

EXEC sp_columns 'Loan';

-- 6. Describing tables with SQL
SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
ORDER BY TABLE_NAME;

SELECT ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE,
       CHARACTER_MAXIMUM_LENGTH AS MaxLength,  -- shorter heading
       NUMERIC_PRECISION AS NumPrecision, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Loan'
ORDER BY ORDINAL_POSITION;

-- 6. Describing tables with SQL
SELECT name AS ForeignKeyName,
       OBJECT_NAME(parent_object_id) AS ChildTable,
       OBJECT_NAME(referenced_object_id) AS ParentTable
FROM sys.foreign_keys
ORDER BY ChildTable, ForeignKeyName;

-- 7. Looking at the data
SELECT TOP (5) *
FROM dbo.Loan
ORDER BY LoanID;

-- 7. Looking at the data
SELECT TOP (3) InstalmentNumber, DueDate, AmountDue,
       PaidDate, AmountPaid, DaysLate
FROM dbo.Payment
WHERE LoanID = 10002
ORDER BY InstalmentNumber DESC;

-- Applied example
USE NorthbridgeLending;
GO

SELECT LoanID, CustomerID, ProductCode, BranchID, OfficerID,
       Principal
FROM dbo.Loan
WHERE LoanID = 10004;

-- Applied example
SELECT CustomerID, FirstName, LastName, City, HomeBranchID
FROM dbo.Customer
WHERE CustomerID = 64;

-- Applied example
SELECT BranchID, BranchName, City
FROM dbo.Branch
WHERE BranchID = 2;

SELECT OfficerID, FirstName, LastName, BranchID
FROM dbo.LoanOfficer
WHERE OfficerID = 105;

-- Applied example
SELECT CollateralID, CollateralType, Description, ValuationAmount
FROM dbo.Collateral
WHERE LoanID = 10004;
