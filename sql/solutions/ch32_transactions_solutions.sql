/* SQL Server from Zero — Volume 2
   Chapter 32: BEGIN TRANSACTION, COMMIT and ROLLBACK — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Every change to a base table is rolled back or reversed: the dataset stays as loaded.
   One error is raised on purpose, in its own batch: 2627 (correction 32.6). */
USE NorthbridgeLending;
GO

-- Start clean: no transaction left open, autocommit mode.
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SET IMPLICIT_TRANSACTIONS OFF;
GO

-- ==============================================================
-- Correction 32.1
-- ==============================================================
PRINT CONCAT(N'Before BEGIN: ', @@TRANCOUNT);

BEGIN TRANSACTION;
PRINT CONCAT(N'After BEGIN: ', @@TRANCOUNT);

COMMIT TRANSACTION;
PRINT CONCAT(N'After COMMIT: ', @@TRANCOUNT);
GO

-- ==============================================================
-- Correction 32.2
-- ==============================================================
BEGIN TRANSACTION;

DELETE FROM dbo.Payment
WHERE LoanID = 10001;                    -- base table, in a transaction

SELECT COUNT(*) AS PaymentsInside
FROM dbo.Payment
WHERE LoanID = 10001;

ROLLBACK TRANSACTION;                    -- every row comes back

SELECT COUNT(*) AS PaymentsAfter
FROM dbo.Payment
WHERE LoanID = 10001;
GO

-- ==============================================================
-- Correction 32.3
-- ==============================================================
DECLARE @Changed INT;

BEGIN TRANSACTION RateReview;

UPDATE dbo.Loan
SET InterestRate = InterestRate - 0.50
WHERE ProductCode = 'PL-STD'
  AND LoanStatus = N'Active';
SET @Changed = @@ROWCOUNT;               -- before any other statement

SELECT @Changed          AS RowsChanged,
       MIN(InterestRate) AS LowestRate,
       MAX(InterestRate) AS HighestRate
FROM dbo.Loan
WHERE ProductCode = 'PL-STD'
  AND LoanStatus = N'Active';

ROLLBACK TRANSACTION RateReview;         -- the exact name

SELECT MIN(InterestRate) AS LowestRate,
       MAX(InterestRate) AS HighestRate
FROM dbo.Loan
WHERE ProductCode = 'PL-STD'
  AND LoanStatus = N'Active';
GO

-- ==============================================================
-- Correction 32.4
-- ==============================================================
DECLARE @Changed INT;

BEGIN TRANSACTION;

UPDATE dbo.Customer
SET Phone = '07700 900123'
WHERE CustomerID = 2;                    -- the primary key
SET @Changed = @@ROWCOUNT;

IF @Changed = 1
BEGIN
    COMMIT TRANSACTION;
    PRINT N'Committed: one customer updated.';
END
ELSE
BEGIN
    ROLLBACK TRANSACTION;
    PRINT CONCAT(N'Rolled back: ', @Changed, N' rows matched.');
END;

BEGIN TRANSACTION;                       -- compensating transaction
UPDATE dbo.Customer
SET Phone = NULL                         -- the value before
WHERE CustomerID = 2;
COMMIT TRANSACTION;

SELECT CustomerID, FirstName, LastName, Phone
FROM dbo.Customer
WHERE CustomerID = 2;
GO

-- ==============================================================
-- Correction 32.5
-- ==============================================================
SET IMPLICIT_TRANSACTIONS ON;

DELETE FROM dbo.CreditRating
WHERE RatingDate < '2023-01-01';         -- opens a transaction

PRINT CONCAT(N'Open transactions: ', @@TRANCOUNT);

ROLLBACK TRANSACTION;

SET IMPLICIT_TRANSACTIONS OFF;

SELECT COUNT(*) AS Ratings
FROM dbo.CreditRating;
GO

-- ==============================================================
-- Correction 32.6
-- ==============================================================
-- Fails on purpose with Msg 2627 (PaymentID 1 exists); the batch continues
-- and the transaction stays open with the status change in it.
BEGIN TRANSACTION;

UPDATE dbo.Loan
SET LoanStatus = N'Default'
WHERE LoanID = 10430;                    -- was Arrears

INSERT INTO dbo.Payment                  -- PaymentID 1 exists
    (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
     PaidDate, AmountPaid, DaysLate)
VALUES (1, 10430, 99, '2026-09-30', 784.33, NULL, 0.00, NULL);

PRINT CONCAT(N'Open transactions: ', @@TRANCOUNT);

SELECT LoanID, LoanStatus
FROM dbo.Loan
WHERE LoanID = 10430;
GO
IF @@TRANCOUNT > 0
    ROLLBACK TRANSACTION;

SELECT LoanID, LoanStatus
FROM dbo.Loan
WHERE LoanID = 10430;
GO

-- ==============================================================
-- Correction 32.7
-- ==============================================================
DECLARE @PayRows INT, @LoanRows INT, @NewBalance DECIMAL(12,2);

BEGIN TRANSACTION;

UPDATE dbo.Payment
SET PaidDate   = '2026-09-30',
    AmountPaid = AmountDue,
    DaysLate   = DATEDIFF(day, DueDate, '2026-09-30')
WHERE PaymentID = 9529
  AND LoanID    = 10430
  AND PaidDate IS NULL                   -- still unpaid
  AND AmountDue = 784.33;
SET @PayRows = @@ROWCOUNT;

UPDATE dbo.Loan
SET OutstandingBalance = OutstandingBalance - 784.33
WHERE LoanID = 10430;
SET @LoanRows = @@ROWCOUNT;

SELECT @NewBalance = OutstandingBalance  -- one row: the key
FROM dbo.Loan
WHERE LoanID = 10430;

IF @PayRows = 1 AND @LoanRows = 1 AND @NewBalance >= 0
BEGIN
    COMMIT TRANSACTION;
    PRINT N'Posting committed.';
END
ELSE
BEGIN
    ROLLBACK TRANSACTION;
    PRINT N'Posting rolled back.';
END;

SELECT p.PaymentID, p.PaidDate, p.AmountPaid, p.DaysLate,
       l.OutstandingBalance
FROM dbo.Payment AS p
INNER JOIN dbo.Loan AS l
    ON l.LoanID = p.LoanID
WHERE p.PaymentID = 9529;
GO
BEGIN TRANSACTION;                       -- compensating transaction

UPDATE dbo.Payment
SET PaidDate = NULL, AmountPaid = 0.00, DaysLate = NULL
WHERE PaymentID = 9529;

UPDATE dbo.Loan
SET OutstandingBalance = OutstandingBalance + 784.33
WHERE LoanID = 10430;

COMMIT TRANSACTION;

SELECT p.PaymentID, p.PaidDate, p.AmountPaid, p.DaysLate,
       l.OutstandingBalance
FROM dbo.Payment AS p
INNER JOIN dbo.Loan AS l
    ON l.LoanID = p.LoanID
WHERE p.PaymentID = 9529;
GO

-- ==============================================================
-- Correction 32.8
-- ==============================================================
BEGIN TRANSACTION;

UPDATE dbo.Loan
SET OutstandingBalance = 0.00
WHERE LoanStatus = N'Written Off';

DELETE p
FROM dbo.Payment AS p
INNER JOIN dbo.Loan AS l
    ON l.LoanID = p.LoanID
WHERE l.LoanStatus = N'Written Off'
  AND p.PaidDate IS NULL;                -- missed instalments only

SELECT SUM(OutstandingBalance) AS WrittenOffBalance
FROM dbo.Loan
WHERE LoanStatus = N'Written Off';

SELECT COUNT(*) - COUNT(PaidDate) AS MissedInstalments
FROM dbo.Payment;

ROLLBACK TRANSACTION;                    -- a rehearsal: undo all

SELECT SUM(OutstandingBalance) AS WrittenOffBalance
FROM dbo.Loan
WHERE LoanStatus = N'Written Off';

SELECT COUNT(*) - COUNT(PaidDate) AS MissedInstalments
FROM dbo.Payment;
GO

-- ==============================================================
-- Clean-up: no transaction may stay open; autocommit mode restored.
-- The base tables are as loaded.
-- ==============================================================
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SET IMPLICIT_TRANSACTIONS OFF;
GO
