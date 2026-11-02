/* SQL Server from Zero — Volume 1
   Chapter 11: Control of flow
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- 1. BEGIN … END: a block of statements

BEGIN
    PRINT 'First statement of the block';
    PRINT 'Second statement of the block';
END;
GO


-- 2. IF … ELSE: making a decision

DECLARE @BranchID INT = 3;
DECLARE @Limit INT = 5;
DECLARE @Arrears INT;

SELECT @Arrears = COUNT(*)
FROM dbo.Loan
WHERE BranchID = @BranchID
  AND LoanStatus = N'Arrears';

IF @Arrears > @Limit
BEGIN
    PRINT CONCAT('Branch ', @BranchID, ': ', @Arrears,
                 ' loans in arrears, above the limit of ', @Limit);
    PRINT 'Report to the credit risk committee.';
END
ELSE
    PRINT CONCAT('Branch ', @BranchID, ' is within the limit.');
GO

DECLARE @Score SMALLINT, @Grade CHAR(1);

SET @Score = (SELECT CreditScore
              FROM dbo.Customer
              WHERE CustomerID = 42);

IF @Score >= 850
    SET @Grade = 'A';
ELSE IF @Score >= 750
    SET @Grade = 'B';
ELSE IF @Score >= 650
    SET @Grade = 'C';
ELSE IF @Score >= 550
    SET @Grade = 'D';
ELSE
    SET @Grade = 'E';

PRINT CONCAT('Customer 42: score ', @Score, ', grade ', @Grade);
GO

DECLARE @Arrears INT = 3;

IF @Arrears > 5
    PRINT 'Above the limit.';
    PRINT 'Report to the credit risk committee.';
GO


-- 3. IF EXISTS: testing whether rows or objects exist

IF EXISTS (SELECT 1
           FROM dbo.Loan
           WHERE BranchID = 6
             AND LoanStatus = N'Written Off')
    PRINT 'Glasgow has written-off loans: include them in the report.';
ELSE
    PRINT 'Glasgow has no written-off loans.';
GO

SELECT LoanID, OutstandingBalance
INTO #Work
FROM dbo.Loan
WHERE LoanStatus = N'Arrears';

IF OBJECT_ID(N'tempdb..#Work', N'U') IS NOT NULL
BEGIN
    PRINT 'The work table exists: dropping it.';
    DROP TABLE #Work;
END;

IF OBJECT_ID(N'tempdb..#Work', N'U') IS NULL
    PRINT 'The work table is gone.';
GO


-- 4. WHILE: repeating statements

DECLARE @BranchID INT = 1;
DECLARE @Active INT;

WHILE @BranchID <= 8
BEGIN
    SELECT @Active = COUNT(*)
    FROM dbo.Loan
    WHERE BranchID = @BranchID
      AND LoanStatus = N'Active';

    PRINT CONCAT('Branch ', @BranchID, ': ', @Active, ' active loans');

    SET @BranchID += 1;                  -- move to the next branch
END;
GO


-- 5. BREAK and CONTINUE: leaving or skipping inside a loop

DECLARE @BranchID INT = 1;
DECLARE @Balance DECIMAL(12,2);
DECLARE @Threshold DECIMAL(12,2) = 1500000.00;

WHILE @BranchID <= 8
BEGIN
    SELECT @Balance = SUM(OutstandingBalance)
    FROM dbo.Loan
    WHERE BranchID = @BranchID
      AND LoanStatus IN (N'Arrears', N'Default', N'Written Off');

    IF @Balance > @Threshold
    BEGIN
        PRINT CONCAT('Branch ', @BranchID, ' exceeds the threshold: ',
                     @Balance);
        BREAK;                           -- stop searching
    END;

    PRINT CONCAT('Branch ', @BranchID, ' is below: ', @Balance);
    SET @BranchID += 1;
END;

PRINT CONCAT('Search stopped at branch ', @BranchID);
GO

DECLARE @BranchID INT = 0;
DECLARE @Arrears INT;

WHILE @BranchID < 8
BEGIN
    SET @BranchID += 1;                  -- increment first

    SELECT @Arrears = COUNT(*)
    FROM dbo.Loan
    WHERE BranchID = @BranchID
      AND LoanStatus = N'Arrears';

    IF @Arrears = 0
        CONTINUE;                        -- nothing to report

    PRINT CONCAT('Branch ', @BranchID, ': ', @Arrears,
                 ' loans in arrears');
END;
GO


-- 6. GOTO, labels and RETURN

DECLARE @LoanID INT = 10999;
DECLARE @Status NVARCHAR(20);

SET @Status = (SELECT LoanStatus
               FROM dbo.Loan
               WHERE LoanID = @LoanID);

IF @Status IS NULL
    GOTO NotFound;

PRINT CONCAT('Loan ', @LoanID, ' has status ', @Status);
GOTO Finish;

NotFound:
    PRINT CONCAT('Loan ', @LoanID, ' does not exist.');

Finish:
    PRINT 'End of check.';
GO

DECLARE @Arrears INT = (SELECT COUNT(*)
                        FROM dbo.Loan
                        WHERE BranchID = 2
                          AND LoanStatus = N'Arrears');

IF @Arrears = 0
BEGIN
    PRINT 'Branch 2 has no loans in arrears: nothing to report.';
    RETURN;                              -- end of this batch
END;

PRINT 'This line runs only when there is something to report.';
GO

PRINT 'The next batch runs normally.';
GO


-- 7. WAITFOR: pausing a script

DECLARE @Start DATETIME2 = SYSDATETIME();

WAITFOR DELAY '00:00:02';                -- two seconds

PRINT CONCAT('Waited at least 2 seconds: ',
             IIF(DATEDIFF(MILLISECOND, @Start, SYSDATETIME()) >= 2000,
                 'yes', 'no'));
GO


-- Applied example (steps run together as one batch)


-- Step 1. Read the loan parameters.

SET NOCOUNT ON;

DECLARE @LoanID INT = 10426;
DECLARE @Balance DECIMAL(12,2), @Rate DECIMAL(5,2),
        @Term SMALLINT, @Payment DECIMAL(12,2);

SELECT @Balance = Principal,
       @Rate    = InterestRate,
       @Term    = TermMonths,
       @Payment = MonthlyPayment
FROM dbo.Loan
WHERE LoanID = @LoanID;                  -- primary key: one row

IF @Balance IS NULL
BEGIN
    PRINT CONCAT('Loan ', @LoanID, ' not found.');
    RETURN;
END;

PRINT CONCAT('Loan ', @LoanID, ': ', @Balance, ' at ', @Rate,
             '% over ', @Term, ' months, payment ', @Payment);


-- Step 2. Build the schedule with WHILE.

DECLARE @Schedule TABLE
(
    InstalmentNo  SMALLINT      NOT NULL PRIMARY KEY,
    Payment       DECIMAL(12,2) NOT NULL,
    Interest      DECIMAL(12,2) NOT NULL,
    PrincipalPart DECIMAL(12,2) NOT NULL,
    Balance       DECIMAL(12,2) NOT NULL
);
DECLARE @k SMALLINT = 1;
DECLARE @Interest DECIMAL(12,2), @Pay DECIMAL(12,2);

WHILE @k <= @Term AND @Balance > 0
BEGIN
    -- interest on the balance at the start of the month
    SET @Interest = ROUND(@Balance * @Rate / 1200, 2);

    IF @k = @Term OR @Balance + @Interest < @Payment
        SET @Pay = @Balance + @Interest;     -- last: clear the balance
    ELSE
        SET @Pay = @Payment;

    SET @Balance -= (@Pay - @Interest);      -- principal repaid

    INSERT INTO @Schedule
        (InstalmentNo, Payment, Interest, PrincipalPart, Balance)
    VALUES (@k, @Pay, @Interest, @Pay - @Interest, @Balance);

    SET @k += 1;
END;

PRINT CONCAT('Instalments generated: ', @k - 1);


-- Step 3. Look at the first eight instalments.

SELECT TOP (8) InstalmentNo, Payment, Interest, PrincipalPart, Balance
FROM @Schedule
ORDER BY InstalmentNo;


-- Step 4. Check the end of the schedule and reconcile with the database.

SELECT InstalmentNo, Payment, Interest, PrincipalPart, Balance
FROM @Schedule
WHERE InstalmentNo >= 22
ORDER BY InstalmentNo;

SELECT
    SUM(Payment)  AS TotalPaid,
    SUM(Interest) AS TotalInterest
FROM @Schedule;

SELECT
    s.Balance            AS ScheduleBalance,
    l.OutstandingBalance AS DatabaseBalance
FROM @Schedule AS s
INNER JOIN dbo.Loan AS l
    ON l.LoanID = @LoanID
WHERE s.InstalmentNo = (SELECT COUNT(*)
                        FROM dbo.Payment
                        WHERE LoanID = @LoanID);

SET NOCOUNT OFF;

GO
