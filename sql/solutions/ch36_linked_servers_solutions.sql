/* SQL Server from Zero — Volume 2
   Chapter 36: Linked servers, distributed transactions and external data — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Server-level objects: linked servers NORTHBRIDGE_LOOP and NORTHBRIDGE_LOOP2, created here
   and removed by the clean-up block at the end. */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Exercise setup: the linked server of section 2, with rpc out on
-- ==============================================================

-- Leftovers of the chapter script or of an earlier run
IF EXISTS (SELECT 1 FROM sys.servers
           WHERE name = N'NORTHBRIDGE_LOOP2')
    EXEC sys.sp_dropserver N'NORTHBRIDGE_LOOP2', 'droplogins';
IF EXISTS (SELECT 1 FROM sys.servers
           WHERE name = N'NORTHBRIDGE_LOOP')
    EXEC sys.sp_dropserver N'NORTHBRIDGE_LOOP', 'droplogins';
GO
DROP TABLE IF EXISTS dbo.Practice_DrLoan;
DROP PROCEDURE IF EXISTS dbo.usp_RemoteBranchArrears;
DROP USER IF EXISTS nb_link_reader;
GO
-- The chapter script's login, if its clean-up could not drop it
DECLARE @Waited INT = 0;
WHILE EXISTS (SELECT 1 FROM sys.dm_exec_sessions
              WHERE login_name = N'nb_link_reader')
      AND @Waited < 60
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @Waited += 1;
END;
IF EXISTS (SELECT 1 FROM sys.server_principals
           WHERE name = N'nb_link_reader')
   AND NOT EXISTS (SELECT 1 FROM sys.dm_exec_sessions
                   WHERE login_name = N'nb_link_reader')
    DROP LOGIN nb_link_reader;
GO

EXEC sys.sp_addlinkedserver
    @server     = N'NORTHBRIDGE_LOOP',
    @srvproduct = N'',
    @provider   = N'MSOLEDBSQL',
    @datasrc    = N'localhost',
    @provstr    = N'Encrypt=yes;TrustServerCertificate=yes',
    @catalog    = N'NorthbridgeLending';
EXEC sys.sp_serveroption N'NORTHBRIDGE_LOOP', 'rpc out', 'true';
GO
EXEC sys.sp_testlinkedserver N'NORTHBRIDGE_LOOP';
GO


-- ==============================================================
-- Correction 36.1
-- ==============================================================

SELECT name,
       provider,
       data_source,
       is_data_access_enabled AS DataAccess,
       is_rpc_out_enabled     AS RpcOut
FROM sys.servers
WHERE is_linked = 1            -- exclude row 0, the local server
ORDER BY name;
GO


-- ==============================================================
-- Correction 36.2
-- ==============================================================

SELECT c.EmploymentStatus,
       COUNT(*) AS Customers
FROM NORTHBRIDGE_LOOP.NorthbridgeLending.dbo.Customer AS c
GROUP BY c.EmploymentStatus
ORDER BY c.EmploymentStatus;
GO


-- ==============================================================
-- Correction 36.3
-- ==============================================================

SELECT LoanID, CustomerID, OutstandingBalance
FROM OPENQUERY(NORTHBRIDGE_LOOP,
    'SELECT TOP (5) LoanID, CustomerID, OutstandingBalance
     FROM dbo.Loan
     WHERE LoanStatus = N''Default''
     ORDER BY OutstandingBalance DESC;') AS q
ORDER BY OutstandingBalance DESC;     -- order of the final result
GO


-- ==============================================================
-- Correction 36.4
-- ==============================================================

EXEC (N'SELECT COUNT(*) AS Loans,
               SUM(OutstandingBalance) AS Balance
        FROM dbo.Loan
        WHERE BranchID = ?           -- first value
          AND LoanStatus = ?;',      -- second value
      6, N'Arrears') AT NORTHBRIDGE_LOOP;
GO


-- ==============================================================
-- Correction 36.5
-- ==============================================================

EXEC sys.sp_addlinkedserver
    @server     = N'NORTHBRIDGE_LOOP2',
    @srvproduct = N'',
    @provider   = N'MSOLEDBSQL',
    @datasrc    = N'localhost',
    @provstr    = N'Encrypt=yes;TrustServerCertificate=yes',
    @catalog    = N'master';
EXEC sys.sp_serveroption N'NORTHBRIDGE_LOOP2', 'connect timeout', 15;
EXEC sys.sp_serveroption N'NORTHBRIDGE_LOOP2', 'query timeout', 60;
GO
EXEC sys.sp_testlinkedserver N'NORTHBRIDGE_LOOP2';
GO
SELECT name, connect_timeout, query_timeout
FROM sys.servers
WHERE name = N'NORTHBRIDGE_LOOP2';
GO
EXEC sys.sp_dropserver N'NORTHBRIDGE_LOOP2', 'droplogins';
GO
SELECT COUNT(*) AS Remaining
FROM sys.servers
WHERE name = N'NORTHBRIDGE_LOOP2';
GO


-- ==============================================================
-- Correction 36.6
-- ==============================================================

SELECT DueMonth, Instalments, AmountPaid, Missed
FROM OPENQUERY(NORTHBRIDGE_LOOP,
    'SELECT MONTH(DueDate) AS DueMonth,
            COUNT(*)        AS Instalments,
            SUM(AmountPaid) AS AmountPaid,
            SUM(CASE WHEN PaidDate IS NULL THEN 1 ELSE 0 END)
                            AS Missed
     FROM dbo.Payment
     WHERE DueDate >= ''2026-07-01''
       AND DueDate <  ''2026-10-01''
     GROUP BY MONTH(DueDate);') AS q
ORDER BY DueMonth;
GO


-- ==============================================================
-- Correction 36.7
-- ==============================================================

EXEC (N'
SET NOCOUNT ON;
DROP TABLE IF EXISTS dbo.Practice_DrLoan;
SELECT LoanID, LoanStatus, OutstandingBalance
INTO dbo.Practice_DrLoan               -- remote copy
FROM dbo.Loan;
UPDATE dbo.Practice_DrLoan
SET LoanStatus = N''Default''          -- simulated drift
WHERE LoanID IN (10007, 10196, 10430);
') AT NORTHBRIDGE_LOOP;
GO

SELECT LoanID, LoanStatus, OutstandingBalance
FROM dbo.Loan                                   -- local truth
EXCEPT
SELECT LoanID, LoanStatus, OutstandingBalance
FROM NORTHBRIDGE_LOOP.NorthbridgeLending.dbo.Practice_DrLoan
ORDER BY LoanID;
GO


-- ==============================================================
-- Correction 36.8
-- ==============================================================

CREATE OR ALTER PROCEDURE dbo.usp_RemoteBranchArrears
    @BranchID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Inner NVARCHAR(400), @Sql NVARCHAR(MAX);

    -- the remote query; @BranchID is an INT: no injection possible
    SET @Inner = N'SELECT LoanID, OutstandingBalance FROM dbo.Loan '
               + N'WHERE LoanStatus = N''Arrears'' AND BranchID = '
               + CAST(@BranchID AS NVARCHAR(10)) + N';';

    -- wrap it in an OPENQUERY literal: every quote doubled once more
    SET @Sql = N'SELECT LoanID, OutstandingBalance '
             + N'FROM OPENQUERY(NORTHBRIDGE_LOOP, '''
             + REPLACE(@Inner, N'''', N'''''')
             + N''') ORDER BY LoanID;';

    EXEC sys.sp_executesql @Sql;
END;
GO

EXEC dbo.usp_RemoteBranchArrears @BranchID = 6;
GO


-- ==============================================================
-- Clean-up: remove every object created by the exercises
-- ==============================================================

DROP PROCEDURE IF EXISTS dbo.usp_RemoteBranchArrears;
DROP TABLE IF EXISTS dbo.Practice_DrLoan;
GO
IF EXISTS (SELECT 1 FROM sys.servers
           WHERE name = N'NORTHBRIDGE_LOOP2')
    EXEC sys.sp_dropserver N'NORTHBRIDGE_LOOP2', 'droplogins';
IF EXISTS (SELECT 1 FROM sys.servers
           WHERE name = N'NORTHBRIDGE_LOOP')
    EXEC sys.sp_dropserver N'NORTHBRIDGE_LOOP', 'droplogins';
GO
SELECT COUNT(*) AS LinkedServersLeft
FROM sys.servers
WHERE name IN (N'NORTHBRIDGE_LOOP', N'NORTHBRIDGE_LOOP2');
GO
