/* SQL Server from Zero — Volume 1
   Chapter 17: Cursors
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

/* The corrections only read the base tables; results go to the Messages
   tab or to table variables. No clean-up is needed. */

-- Correction 17.1
DECLARE @Code VARCHAR(10), @Name NVARCHAR(60);   -- column types

DECLARE ProductCursor CURSOR LOCAL FAST_FORWARD
FOR
    SELECT ProductCode, ProductName
    FROM dbo.Product
    ORDER BY ProductCode;

OPEN ProductCursor;
FETCH NEXT FROM ProductCursor INTO @Code, @Name;  -- first row

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT CONCAT(@Code, N' - ', @Name);
    FETCH NEXT FROM ProductCursor INTO @Code, @Name;  -- next row
END;

CLOSE ProductCursor;
DEALLOCATE ProductCursor;
GO

-- Correction 17.2
DECLARE @First NVARCHAR(40), @Last NVARCHAR(40);

DECLARE OfficerCursor CURSOR LOCAL FAST_FORWARD
FOR
    SELECT FirstName, LastName
    FROM dbo.LoanOfficer
    WHERE BranchID = 8                -- Newcastle Quayside
    ORDER BY OfficerID;

OPEN OfficerCursor;
FETCH NEXT FROM OfficerCursor INTO @First, @Last;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT CONCAT(@First, N' ', @Last);
    FETCH NEXT FROM OfficerCursor INTO @First, @Last;
END;

CLOSE OfficerCursor;
DEALLOCATE OfficerCursor;
GO

-- Correction 17.3
DECLARE @CustomerID INT;
DECLARE @Count INT = 0;                     -- start at 0, not NULL

DECLARE RetiredCursor CURSOR LOCAL FAST_FORWARD
FOR
    SELECT CustomerID
    FROM dbo.Customer
    WHERE EmploymentStatus = N'Retired'
    ORDER BY CustomerID;

OPEN RetiredCursor;
FETCH NEXT FROM RetiredCursor INTO @CustomerID;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Count = @Count + 1;                -- one more customer
    FETCH NEXT FROM RetiredCursor INTO @CustomerID;
END;

CLOSE RetiredCursor;
DEALLOCATE RetiredCursor;

PRINT CONCAT(N'Retired customers: ', @Count);

SELECT COUNT(*) AS RetiredCustomers        -- the set-based answer
FROM dbo.Customer
WHERE EmploymentStatus = N'Retired';
GO

-- Correction 17.4
DECLARE @Name NVARCHAR(60), @Opened DATE;

DECLARE OpenCursor CURSOR LOCAL SCROLL STATIC READ_ONLY
FOR
    SELECT BranchName, OpenedDate
    FROM dbo.Branch
    ORDER BY OpenedDate;

OPEN OpenCursor;

FETCH LAST FROM OpenCursor INTO @Name, @Opened;        -- row 8
PRINT CONCAT(N'LAST       : ', @Name, N' ', @Opened);

FETCH ABSOLUTE 2 FROM OpenCursor INTO @Name, @Opened;  -- row 2
PRINT CONCAT(N'ABSOLUTE 2 : ', @Name, N' ', @Opened);

FETCH RELATIVE 3 FROM OpenCursor INTO @Name, @Opened;  -- row 5
PRINT CONCAT(N'RELATIVE 3 : ', @Name, N' ', @Opened);

FETCH PRIOR FROM OpenCursor INTO @Name, @Opened;       -- row 4
PRINT CONCAT(N'PRIOR      : ', @Name, N' ', @Opened);

CLOSE OpenCursor;
DEALLOCATE OpenCursor;
GO

-- Correction 17.5
DECLARE @No SMALLINT, @Paid DECIMAL(12,2);
DECLARE @Running DECIMAL(12,2) = 0;         -- the running total

DECLARE RunCursor CURSOR LOCAL FAST_FORWARD
FOR
    SELECT InstalmentNumber, AmountPaid
    FROM dbo.Payment
    WHERE LoanID = 10001
      AND InstalmentNumber <= 6
    ORDER BY InstalmentNumber;

OPEN RunCursor;
FETCH NEXT FROM RunCursor INTO @No, @Paid;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Running = @Running + @Paid;        -- add this instalment
    PRINT CONCAT(@No, N': ', @Running);
    FETCH NEXT FROM RunCursor INTO @No, @Paid;
END;

CLOSE RunCursor;
DEALLOCATE RunCursor;

SELECT                                      -- the set-based answer
    InstalmentNumber,
    SUM(AmountPaid) OVER (ORDER BY InstalmentNumber
                          ROWS UNBOUNDED PRECEDING) AS RunningPaid
FROM dbo.Payment
WHERE LoanID = 10001
  AND InstalmentNumber <= 6
ORDER BY InstalmentNumber;
GO

-- Correction 17.6
-- Exercise 17.6: the colleague's script as given; it fails with
-- Msg 16924 (one variable for two columns), so it is commented out.
-- DECLARE @Name NVARCHAR(60);
--
-- DECLARE OfficerCursor CURSOR LOCAL FAST_FORWARD
-- FOR
--     SELECT FirstName, LastName
--     FROM dbo.LoanOfficer
--     WHERE BranchID = 1
--     ORDER BY OfficerID;
--
-- OPEN OfficerCursor;
-- WHILE @@FETCH_STATUS = 0
-- BEGIN
--     FETCH NEXT FROM OfficerCursor INTO @Name;
--     PRINT @Name;
-- END;

-- The corrected script.
DECLARE @First NVARCHAR(40), @Last NVARCHAR(40);  -- one per column

DECLARE OfficerCursor CURSOR LOCAL FAST_FORWARD
FOR
    SELECT FirstName, LastName
    FROM dbo.LoanOfficer
    WHERE BranchID = 1
    ORDER BY OfficerID;

OPEN OfficerCursor;
FETCH NEXT FROM OfficerCursor INTO @First, @Last; -- fetch first

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT CONCAT(@First, N' ', @Last);            -- use the row
    FETCH NEXT FROM OfficerCursor INTO @First, @Last; -- then fetch
END;

CLOSE OfficerCursor;                              -- end clearly
DEALLOCATE OfficerCursor;
GO

-- Correction 17.7
SET NOCOUNT ON;

DECLARE @Best TABLE (
    BranchID INT, OfficerID INT, LastName NVARCHAR(40), Loans INT);
DECLARE @BranchID INT;

DECLARE BranchCursor CURSOR LOCAL FAST_FORWARD
FOR
    SELECT BranchID FROM dbo.Branch ORDER BY BranchID;

OPEN BranchCursor;
FETCH NEXT FROM BranchCursor INTO @BranchID;

WHILE @@FETCH_STATUS = 0
BEGIN
    INSERT INTO @Best (BranchID, OfficerID, LastName, Loans)
    SELECT TOP (1)
        @BranchID,
        o.OfficerID,
        o.LastName,
        COUNT(*)
    FROM dbo.Loan AS l
    INNER JOIN dbo.LoanOfficer AS o
        ON o.OfficerID = l.OfficerID
    WHERE l.BranchID = @BranchID
    GROUP BY o.OfficerID, o.LastName
    ORDER BY COUNT(*) DESC, o.OfficerID;      -- tie: lower ID

    FETCH NEXT FROM BranchCursor INTO @BranchID;
END;

CLOSE BranchCursor;
DEALLOCATE BranchCursor;

SELECT BranchID, OfficerID, LastName, Loans
FROM @Best
ORDER BY BranchID;
GO

-- Correction 17.8
-- Exercise 17.8: the colleague's cursor as given, run on its own.
SET NOCOUNT ON;
DECLARE @Result TABLE (BranchID INT, Defaults INT,
                       Exposure DECIMAL(12,2));
DECLARE @BranchID INT;

DECLARE B CURSOR LOCAL FAST_FORWARD
FOR SELECT BranchID FROM dbo.Branch ORDER BY BranchID;

OPEN B;
FETCH NEXT FROM B INTO @BranchID;
WHILE @@FETCH_STATUS = 0
BEGIN
    INSERT INTO @Result
    SELECT @BranchID, COUNT(*), ISNULL(SUM(OutstandingBalance), 0)
    FROM dbo.Loan
    WHERE BranchID = @BranchID
      AND LoanStatus = N'Default';

    FETCH NEXT FROM B INTO @BranchID;
END;
CLOSE B;
DEALLOCATE B;

SELECT * FROM @Result ORDER BY BranchID;
GO

-- The correction.
SET NOCOUNT ON;
DECLARE @Result TABLE (BranchID INT, Defaults INT,
                       Exposure DECIMAL(12,2));
DECLARE @BranchID INT;

-- The colleague's cursor, unchanged.
DECLARE B CURSOR LOCAL FAST_FORWARD
FOR SELECT BranchID FROM dbo.Branch ORDER BY BranchID;

OPEN B;
FETCH NEXT FROM B INTO @BranchID;
WHILE @@FETCH_STATUS = 0
BEGIN
    INSERT INTO @Result
    SELECT @BranchID, COUNT(*), ISNULL(SUM(OutstandingBalance), 0)
    FROM dbo.Loan
    WHERE BranchID = @BranchID
      AND LoanStatus = N'Default';

    FETCH NEXT FROM B INTO @BranchID;
END;
CLOSE B;
DEALLOCATE B;

-- The set-based version.
SELECT
    b.BranchID,
    COUNT(l.LoanID)                     AS Defaults,
    ISNULL(SUM(l.OutstandingBalance), 0) AS Exposure
FROM dbo.Branch AS b
LEFT JOIN dbo.Loan AS l
    ON l.BranchID = b.BranchID
   AND l.LoanStatus = N'Default'       -- condition in the ON
GROUP BY b.BranchID
ORDER BY b.BranchID;

-- The proof: rows of the cursor result missing from the set result.
SELECT COUNT(*) AS Differences
FROM (
    SELECT BranchID, Defaults, Exposure FROM @Result
    EXCEPT
    SELECT
        b.BranchID,
        COUNT(l.LoanID),
        ISNULL(SUM(l.OutstandingBalance), 0)
    FROM dbo.Branch AS b
    LEFT JOIN dbo.Loan AS l
        ON l.BranchID = b.BranchID
       AND l.LoanStatus = N'Default'
    GROUP BY b.BranchID
) AS d;
GO
