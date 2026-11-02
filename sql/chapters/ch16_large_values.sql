/* SQL Server from Zero — Volume 1
   Chapter 16: Large values: NVARCHAR(MAX), VARBINARY(MAX) and the deprecated text commands
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

/* Files: section 6 reads C:\NorthbridgeData\ (Windows). On Docker, use
   /var/opt/mssql/data/import/ instead (see chapter 15, section 1).
   This script creates its own tables only; no base table is changed. */

-- 1. The limits of the (n) types and the MAX types
-- Fails on purpose with Msg 131: VARCHAR(n) cannot exceed 8000.
-- DECLARE @Memo VARCHAR(9000);
DECLARE @Memo VARCHAR(MAX) = 'Committee minutes, 30 September 2026';

SELECT
    @Memo      AS Memo,
    LEN(@Memo) AS Characters;
GO

-- 2. Measuring values: LEN and DATALENGTH
SELECT
    CustomerID,
    LEN(FirstName)        AS LenFirstName,
    DATALENGTH(FirstName) AS BytesFirstName,
    LEN(Postcode)         AS LenPostcode,
    DATALENGTH(Postcode)  AS BytesPostcode
FROM dbo.Customer
WHERE CustomerID <= 3
ORDER BY CustomerID;
GO
SELECT
    LEN(N'Leeds   ')        AS Characters,
    DATALENGTH(N'Leeds   ') AS Bytes,
    DATALENGTH(NULL)        AS BytesOfNull;
GO

-- 3. The 8,000-byte trap: building long strings
SELECT
    LEN(REPLICATE('A', 10000))                      AS PlainText,
    LEN(REPLICATE(CAST('A' AS VARCHAR(MAX)), 10000)) AS MaxText,
    LEN(REPLICATE(N'A', 5000))                      AS PlainUnicode;
GO
DECLARE @Long VARCHAR(MAX);

SET @Long = REPLICATE('A', 8000) + REPLICATE('B', 8000);
SELECT LEN(@Long) AS WithoutCast;

SET @Long = CAST(REPLICATE('A', 8000) AS VARCHAR(MAX))
            + REPLICATE('B', 8000);
SELECT LEN(@Long) AS WithCast;
GO

-- 4. Storing credit memos in NVARCHAR(MAX)
DROP TABLE IF EXISTS dbo.CreditMemo;

-- CREATE TABLE: chapter 21 explains it in full.
CREATE TABLE dbo.CreditMemo (
    MemoID   INT           NOT NULL PRIMARY KEY,
    LoanID   INT           NOT NULL,
    MemoText NVARCHAR(MAX) NULL
);

INSERT INTO dbo.CreditMemo (MemoID, LoanID, MemoText)
SELECT
    ROW_NUMBER() OVER (ORDER BY l.LoanID),       -- 1, 2, 3
    l.LoanID,
    CONCAT(N'Loan ', l.LoanID,
           N' (', l.ProductCode, N') for customer ',
           l.CustomerID,
           N' is in default. Outstanding balance: GBP ',
           l.OutstandingBalance, N'.')
FROM dbo.Loan AS l
WHERE l.LoanID IN (10002, 10019, 10041);

SELECT
    MemoID,
    LoanID,
    LEN(MemoText)        AS Characters,
    DATALENGTH(MemoText) AS Bytes,
    LEFT(MemoText, 36)   AS StartOfMemo
FROM dbo.CreditMemo
ORDER BY MemoID;
GO

-- 5. Changing part of a large value: UPDATE … .WRITE
UPDATE dbo.CreditMemo
SET MemoText.WRITE(
        N' Reviewed by the credit committee on 2026-09-30.',
        NULL,        -- offset NULL: append at the end
        NULL)        -- length ignored when appending
WHERE MemoID = 1;

SELECT
    LEN(MemoText)       AS Characters,
    RIGHT(MemoText, 48) AS EndOfMemo
FROM dbo.CreditMemo
WHERE MemoID = 1;
GO
SELECT CHARINDEX(N'default', MemoText) AS PositionFrom1
FROM dbo.CreditMemo
WHERE MemoID = 1;

UPDATE dbo.CreditMemo
SET MemoText.WRITE(
        N'DEFAULT',
        CHARINDEX(N'default', MemoText) - 1,  -- from 0
        7)                                     -- replace 7 chars
WHERE MemoID = 1;

SELECT SUBSTRING(MemoText, 38, 21) AS Middle
FROM dbo.CreditMemo
WHERE MemoID = 1;
GO
UPDATE dbo.CreditMemo
SET MemoText.WRITE(N'', 85, NULL)   -- delete from offset 85 to end
WHERE MemoID = 1;

SELECT LEN(MemoText) AS Characters
FROM dbo.CreditMemo
WHERE MemoID = 1;
GO

-- 6. VARBINARY(MAX): storing documents
SELECT
    CAST('NBL' AS VARBINARY(10))   AS AsVarchar,
    CAST(N'NBL' AS VARBINARY(10))  AS AsNvarchar,
    DATALENGTH(CAST(N'NBL' AS VARBINARY(10))) AS Bytes;
GO
DROP TABLE IF EXISTS dbo.DocumentStore;

CREATE TABLE dbo.DocumentStore (
    DocumentID INT            NOT NULL PRIMARY KEY,
    FileName   NVARCHAR(260)  NOT NULL,
    Content    VARBINARY(MAX) NOT NULL
);

INSERT INTO dbo.DocumentStore (DocumentID, FileName, Content)
SELECT 1, N'Branch.csv', f.BulkColumn
FROM OPENROWSET(
        BULK 'C:\NorthbridgeData\Branch.csv',
        SINGLE_BLOB
     ) AS f;

INSERT INTO dbo.DocumentStore (DocumentID, FileName, Content)
SELECT 2, N'Product.csv', f.BulkColumn
FROM OPENROWSET(
        BULK 'C:\NorthbridgeData\Product.csv',
        SINGLE_BLOB
     ) AS f;

SELECT
    DocumentID,
    FileName,
    DATALENGTH(Content)                         AS Bytes,
    LEFT(CAST(Content AS VARCHAR(MAX)), 11)     AS FirstChars
FROM dbo.DocumentStore
ORDER BY DocumentID;
GO

-- 7. The legacy text, ntext and image types
DROP TABLE IF EXISTS dbo.LegacyMemo;

CREATE TABLE dbo.LegacyMemo (
    MemoID   INT  NOT NULL PRIMARY KEY,
    LoanID   INT  NOT NULL,
    MemoText TEXT NULL                 -- deprecated type
);

INSERT INTO dbo.LegacyMemo (MemoID, LoanID, MemoText)
VALUES
    (1, 10002,
     'Customer called on 2026-09-02 and promised a payment.'),
    (2, 10019, 'No contact since July 2026.');

SELECT
    MemoID,
    DATALENGTH(MemoText) AS Bytes
FROM dbo.LegacyMemo
ORDER BY MemoID;
GO
-- Fails on purpose with Msg 8116: LEN does not accept a text value.
-- SELECT LEN(MemoText) FROM dbo.LegacyMemo;
-- Fails on purpose with Msg 402: = does not accept a text value.
-- SELECT MemoID
-- FROM dbo.LegacyMemo
-- WHERE MemoText = 'No contact since July 2026.';
SET NOCOUNT ON;                        -- chapter 10
DECLARE @ptr VARBINARY(16);            -- a text pointer

SELECT @ptr = TEXTPTR(MemoText)        -- find the pointer
FROM dbo.LegacyMemo
WHERE MemoID = 1;

READTEXT dbo.LegacyMemo.MemoText @ptr 0 8;   -- 8 bytes from 0
GO
SET NOCOUNT ON;
DECLARE @ptr VARBINARY(16);

SELECT @ptr = TEXTPTR(MemoText)
FROM dbo.LegacyMemo
WHERE MemoID = 2;

WRITETEXT dbo.LegacyMemo.MemoText @ptr 'Letter sent on 2026-09-15.';
GO
SET NOCOUNT ON;
DECLARE @ptr VARBINARY(16);

SELECT @ptr = TEXTPTR(MemoText)
FROM dbo.LegacyMemo
WHERE MemoID = 1;

-- insert offset NULL = append; delete length 0 = delete nothing
UPDATETEXT dbo.LegacyMemo.MemoText @ptr NULL 0 ' Payment not received.';

-- at offset 0, delete 8 bytes ('Customer'), insert 'Borrower'
UPDATETEXT dbo.LegacyMemo.MemoText @ptr 0 8 'Borrower';
SET NOCOUNT OFF;                       -- row counts back on
GO
SELECT
    MemoID,
    DATALENGTH(MemoText)       AS Bytes,
    SUBSTRING(MemoText, 1, 34) AS StartOfMemo
FROM dbo.LegacyMemo
ORDER BY MemoID;
GO

-- 8. Migrating to MAX types
SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE DATA_TYPE IN ('text', 'ntext', 'image')
ORDER BY TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME;
GO
ALTER TABLE dbo.LegacyMemo
ALTER COLUMN MemoText VARCHAR(MAX) NULL;
GO
UPDATE dbo.LegacyMemo
SET MemoText = MemoText;
GO
SELECT
    MemoID,
    LEN(MemoText) AS Characters
FROM dbo.LegacyMemo
WHERE MemoText <> 'No contact since July 2026.'
ORDER BY MemoID;
GO

-- Applied example, Step 1. Create the memo table.
DROP TABLE IF EXISTS dbo.CommitteeMemo;

CREATE TABLE dbo.CommitteeMemo (
    LoanID   INT           NOT NULL PRIMARY KEY,
    MemoText NVARCHAR(MAX) NOT NULL    -- never NULL: .WRITE-safe
);
GO

-- Applied example, Step 2. Write one memo per defaulted loan.
INSERT INTO dbo.CommitteeMemo (LoanID, MemoText)
SELECT
    l.LoanID,
    CONCAT(N'Loan ', l.LoanID,
           N' (', l.ProductCode, N') for customer ',
           l.CustomerID,
           N' is in default. Outstanding balance: GBP ',
           l.OutstandingBalance, N'.')
FROM dbo.Loan AS l
WHERE l.LoanStatus = N'Default';

SELECT
    COUNT(*)                  AS Memos,
    SUM(LEN(MemoText))        AS TotalCharacters,
    SUM(DATALENGTH(MemoText)) AS TotalBytes
FROM dbo.CommitteeMemo;
GO

-- Applied example, Step 3. Append the review sentence to every memo.
UPDATE dbo.CommitteeMemo
SET MemoText.WRITE(
        N' Reviewed by the credit committee on 2026-09-30.',
        NULL, NULL);           -- append to every row
GO

-- Applied example, Step 4. Measure the storage again.
SELECT
    COUNT(*)                  AS Memos,
    SUM(LEN(MemoText))        AS TotalCharacters,
    SUM(DATALENGTH(MemoText)) AS TotalBytes,
    MAX(LEN(MemoText))        AS LongestMemo
FROM dbo.CommitteeMemo;
GO

-- Applied example, Step 5. Show the memos of the three largest balances.
SELECT TOP (3)
    m.LoanID,
    l.OutstandingBalance,
    LEN(m.MemoText)               AS Characters,
    SUBSTRING(m.MemoText, 1, 30)  AS StartOfMemo
FROM dbo.CommitteeMemo AS m
INNER JOIN dbo.Loan AS l
    ON l.LoanID = m.LoanID
ORDER BY l.OutstandingBalance DESC;
GO

-- Clean-up: dbo.CreditMemo and dbo.DocumentStore are kept for the
-- exercises; the solutions script drops them. Remove the other tables.
DROP TABLE IF EXISTS dbo.LegacyMemo;
DROP TABLE IF EXISTS dbo.CommitteeMemo;
GO
