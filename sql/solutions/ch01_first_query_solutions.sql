/* SQL Server from Zero — Volume 1
   Chapter 01: Installing SQL Server and writing your first query
   Target: SQL Server 2025 (runs on 2022). */

-- ===== Correction 01.1 =====
SELECT 250 * 12 AS AnnualTotal;  -- 250 per month times 12 months

-- ===== Correction 01.2 =====
SELECT 'Northbridge Lending' AS Company,  -- text: in quotation marks
       8 AS Branches,                     -- number: no quotation marks
       'London' AS HeadOffice;            -- text again

-- ===== Correction 01.3 =====
SELECT 17 / 5   AS A,  -- integer / integer: whole part only
       17 % 5   AS B,  -- remainder of the integer division
       17 / 5.0 AS C,  -- decimal division
       17.0 / 5 AS D;  -- decimal division

-- ===== Correction 01.4 =====
SELECT 239.08 * 48 AS TotalRepaid,             -- 48 instalments of 239.08
       239.08 * 48 - 9600 AS TotalInterest;    -- minus the principal

-- ===== Correction 01.5 =====
SELECT 'Batch one' AS Message;
GO
SELECT 'Batch two' AS Message;
GO
-- Deliberate error: remove the two dashes at the start of the next line to test it.
-- SELECT 'Batch one AS Message;   -- closing quotation mark removed
GO
SELECT 'Batch two' AS Message;
GO

-- ===== Correction 01.6 =====
-- Deliberate error 8134: remove the two dashes to see it.
-- SELECT 1 / 0;    -- error: nothing can be divided by zero
SELECT 1 / 0.5;  -- decimal division: 1 divided by one half

-- ===== Correction 01.7 =====
SELECT 450 / 18000 * 100 AS WrongPercentage,     -- integer division first
       450 * 100.0 / 18000 AS RightPercentage;   -- decimal from the start

-- ===== Correction 01.8 =====
