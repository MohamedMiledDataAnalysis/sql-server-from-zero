/* SQL Server from Zero — Volume 1
   Chapter 04: Filtering rows with WHERE
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Correction 04.1

SELECT OfficerID,
       FirstName,
       LastName,
       HireDate
FROM dbo.LoanOfficer
WHERE BranchID = 3           -- Birmingham New Street
ORDER BY OfficerID;


-- Correction 04.2

SELECT ProductCode,
       ProductName,
       BaseRate
FROM dbo.Product
WHERE IsSecured = 0          -- 0 = no security, 1 = secured
ORDER BY ProductCode;


-- Correction 04.3

SELECT CustomerID,
       FirstName,
       LastName,
       DateOfBirth,
       City
FROM dbo.Customer
WHERE EmploymentStatus = N'Retired'
ORDER BY DateOfBirth;        -- earliest birth date = oldest


-- Correction 04.4

SELECT CustomerID,
       FirstName,
       LastName,
       CreditScore,
       AnnualIncome
FROM dbo.Customer
WHERE CreditScore BETWEEN 550 AND 649   -- grade D, both ends in
  AND AnnualIncome < 20000              -- strictly below £20,000
ORDER BY CreditScore,
         CustomerID;


-- Correction 04.5

SELECT CustomerID,
       FirstName,
       LastName,
       Postcode
FROM dbo.Customer
WHERE Postcode LIKE 'M[0-9]%'     -- M then a digit: Manchester
  AND LastName LIKE N'[A-C]%'     -- first letter A, B or C
ORDER BY LastName,
         FirstName,
         CustomerID;


-- Correction 04.6

SELECT PaymentID,
       LoanID,
       DueDate,
       PaidDate,
       DaysLate
FROM dbo.Payment
WHERE DueDate >= '2026-08-01'     -- 1 August included
  AND DueDate <  '2026-09-01'     -- 1 September excluded
  AND DaysLate > 0                -- paid, and late
ORDER BY DaysLate DESC,
         PaymentID;


-- Correction 04.7

SELECT InstalmentNumber,
       DueDate,
       PaidDate,
       DaysLate
FROM dbo.Payment
WHERE LoanID = 10086
  AND (DaysLate > 0             -- paid late
       OR PaidDate IS NULL)     -- or missed
ORDER BY InstalmentNumber;


-- Correction 04.8

SELECT CustomerID,
       FirstName,
       LastName,
       Email,
       Phone
FROM dbo.Customer
WHERE (Email IS NULL OR Phone IS NULL)        -- at least one missing
  AND NOT (Email IS NULL AND Phone IS NULL)   -- but not both
ORDER BY CustomerID;

