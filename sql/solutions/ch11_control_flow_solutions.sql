/* SQL Server from Zero — Volume 1
   Chapter 11: Control of flow
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Correction 11.1

DECLARE @LoanID INT = 10430;
DECLARE @Status NVARCHAR(20);

SET @Status = (SELECT LoanStatus
               FROM dbo.Loan
               WHERE LoanID = @LoanID);

IF @Status <> N'Active'
    PRINT CONCAT('Loan ', @LoanID,
                 ' needs a collections call (status: ', @Status, ')');
ELSE
    PRINT CONCAT('Loan ', @LoanID, ' is performing');
GO


-- Correction 11.2

IF EXISTS (SELECT 1
           FROM dbo.Loan
           WHERE BranchID = 2
             AND LoanStatus = N'Arrears')
    PRINT 'Branch 2 has loans in arrears';
ELSE
    PRINT 'Branch 2 has no loans in arrears';
GO


-- Correction 11.3

DECLARE @Year INT = 2021;
DECLARE @Loans INT;

WHILE @Year <= 2026
BEGIN
    SELECT @Loans = COUNT(*)
    FROM dbo.Loan
    WHERE YEAR(OriginationDate) = @Year;

    PRINT CONCAT(@Year, ': ', @Loans, ' loans originated');

    SET @Year += 1;                      -- never forget the increment
END;
GO


-- Correction 11.4

DECLARE @CustomerID INT = 4;
DECLARE @Score SMALLINT, @Grade CHAR(1), @PD DECIMAL(6,4);

SET @Score = (SELECT CreditScore
              FROM dbo.Customer
              WHERE CustomerID = @CustomerID);

IF @Score IS NULL
BEGIN
    PRINT CONCAT('Customer ', @CustomerID, ' not found');
    RETURN;                              -- skip the chain
END;

IF @Score >= 850
BEGIN
    SET @Grade = 'A'; SET @PD = 0.0040;
END
ELSE IF @Score >= 750
BEGIN
    SET @Grade = 'B'; SET @PD = 0.0110;
END
ELSE IF @Score >= 650
BEGIN
    SET @Grade = 'C'; SET @PD = 0.0280;
END
ELSE IF @Score >= 550
BEGIN
    SET @Grade = 'D'; SET @PD = 0.0750;
END
ELSE
BEGIN
    SET @Grade = 'E'; SET @PD = 0.1900;
END;

PRINT CONCAT('Customer ', @CustomerID, ': score ', @Score,
             ', grade ', @Grade, ', PD ', @PD);
GO


-- Correction 11.5

DECLARE @Balance DECIMAL(12,2), @Rate DECIMAL(5,2),
        @Payment DECIMAL(12,2), @Term SMALLINT;
DECLARE @k SMALLINT = 1, @Interest DECIMAL(12,2);

SELECT @Balance = Principal, @Rate = InterestRate,
       @Payment = MonthlyPayment, @Term = TermMonths
FROM dbo.Loan
WHERE LoanID = 10426;

WHILE @k <= @Term
BEGIN
    SET @Interest = ROUND(@Balance * @Rate / 1200, 2);
    SET @Balance -= (@Payment - @Interest);

    IF @Balance < 1000.00
    BEGIN
        PRINT CONCAT('Balance below 1000 after instalment ', @k,
                     ': ', @Balance);
        BREAK;                           -- found: stop the loop
    END;

    SET @k += 1;
END;
GO


-- Correction 11.6

DECLARE @Attempt INT = 1;

WHILE @Attempt <= 3
BEGIN
    PRINT CONCAT('Attempt ', @Attempt);

    IF @Attempt < 3
        WAITFOR DELAY '00:00:01';        -- no pause after the last

    SET @Attempt += 1;
END;

PRINT 'Done';
GO


-- Correction 11.7

DECLARE @LoanID INT = 99999;
DECLARE @Product VARCHAR(10), @Status NVARCHAR(20);

SELECT @Product = ProductCode,
       @Status  = LoanStatus
FROM dbo.Loan
WHERE LoanID = @LoanID;                  -- variables start as NULL

IF @Product IS NULL
    GOTO NotFound;

PRINT CONCAT('Loan ', @LoanID, ': product ', @Product,
             ', status ', @Status);
RETURN;                                  -- do not fall into NotFound

NotFound:
    PRINT CONCAT('Loan ', @LoanID, ' not found');
    RETURN;
GO


-- Correction 11.7, second run with an existing loan
DECLARE @LoanID INT = 10007;
DECLARE @Product VARCHAR(10), @Status NVARCHAR(20);

SELECT @Product = ProductCode,
       @Status  = LoanStatus
FROM dbo.Loan
WHERE LoanID = @LoanID;

IF @Product IS NULL
    GOTO NotFound;

PRINT CONCAT('Loan ', @LoanID, ': product ', @Product,
             ', status ', @Status);
RETURN;

NotFound:
    PRINT CONCAT('Loan ', @LoanID, ' not found');
    RETURN;
GO

-- Correction 11.8

SET NOCOUNT ON;

DECLARE @LoanID INT = 10566;
DECLARE @Balance DECIMAL(12,2), @Rate DECIMAL(5,2),
        @Term SMALLINT, @Payment DECIMAL(12,2);
DECLARE @k SMALLINT = 1;
DECLARE @Interest DECIMAL(12,2), @Pay DECIMAL(12,2);
DECLARE @Schedule TABLE
(
    InstalmentNo  SMALLINT      NOT NULL PRIMARY KEY,
    Payment       DECIMAL(12,2) NOT NULL,
    Interest      DECIMAL(12,2) NOT NULL,
    PrincipalPart DECIMAL(12,2) NOT NULL,
    Balance       DECIMAL(12,2) NOT NULL
);

SELECT @Balance = Principal, @Rate = InterestRate,
       @Term = TermMonths, @Payment = MonthlyPayment
FROM dbo.Loan
WHERE LoanID = @LoanID;

WHILE @k <= @Term AND @Balance > 0
BEGIN
    SET @Interest = ROUND(@Balance * @Rate / 1200, 2);
    IF @k = @Term OR @Balance + @Interest < @Payment
        SET @Pay = @Balance + @Interest;     -- final instalment
    ELSE
        SET @Pay = @Payment;
    SET @Balance -= (@Pay - @Interest);
    INSERT INTO @Schedule
        (InstalmentNo, Payment, Interest, PrincipalPart, Balance)
    VALUES (@k, @Pay, @Interest, @Pay - @Interest, @Balance);
    SET @k += 1;
END;

SELECT InstalmentNo, Payment, Interest, PrincipalPart, Balance
FROM @Schedule
WHERE InstalmentNo >= 22
ORDER BY InstalmentNo;

SELECT SUM(Interest) AS TotalInterest
FROM @Schedule;

SELECT s.InstalmentNo, s.Balance AS ScheduleBalance,
       l.OutstandingBalance AS DatabaseBalance
FROM @Schedule AS s
INNER JOIN dbo.Loan AS l
    ON l.LoanID = @LoanID
WHERE s.InstalmentNo = (SELECT COUNT(*)
                        FROM dbo.Payment
                        WHERE LoanID = @LoanID);

SET NOCOUNT OFF;
GO
