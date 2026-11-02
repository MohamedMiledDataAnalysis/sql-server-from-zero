/* SQL Server from Zero — Northbridge Lending dataset
   Step 2 of 3: create the eight tables
   Run in SQL Server Management Studio (SSMS) or sqlcmd. Target: SQL Server 2025 (also runs on 2022). */

USE NorthbridgeLending;
GO

CREATE TABLE dbo.Branch (
    BranchID      INT            NOT NULL CONSTRAINT PK_Branch PRIMARY KEY,
    BranchName    NVARCHAR(60)   NOT NULL,
    City          NVARCHAR(40)   NOT NULL,
    Region        NVARCHAR(40)   NOT NULL,
    OpenedDate    DATE           NOT NULL
);

CREATE TABLE dbo.LoanOfficer (
    OfficerID     INT            NOT NULL CONSTRAINT PK_LoanOfficer PRIMARY KEY,
    FirstName     NVARCHAR(40)   NOT NULL,
    LastName      NVARCHAR(40)   NOT NULL,
    BranchID      INT            NOT NULL CONSTRAINT FK_LoanOfficer_Branch REFERENCES dbo.Branch (BranchID),
    HireDate      DATE           NOT NULL,
    Email         NVARCHAR(100)  NOT NULL
);

CREATE TABLE dbo.Product (
    ProductCode   VARCHAR(10)    NOT NULL CONSTRAINT PK_Product PRIMARY KEY,
    ProductName   NVARCHAR(60)   NOT NULL,
    ProductType   NVARCHAR(20)   NOT NULL,
    BaseRate      DECIMAL(5,2)   NOT NULL,
    MaxTermMonths SMALLINT       NOT NULL,
    IsSecured     BIT            NOT NULL
);

CREATE TABLE dbo.Customer (
    CustomerID       INT            NOT NULL CONSTRAINT PK_Customer PRIMARY KEY,
    FirstName        NVARCHAR(40)   NOT NULL,
    LastName         NVARCHAR(40)   NOT NULL,
    DateOfBirth      DATE           NOT NULL,
    Email            NVARCHAR(100)  NULL,
    Phone            VARCHAR(20)    NULL,
    City             NVARCHAR(40)   NOT NULL,
    Postcode         VARCHAR(10)    NOT NULL,
    EmploymentStatus NVARCHAR(20)   NOT NULL,
    AnnualIncome     DECIMAL(12,2)  NOT NULL,
    CreditScore      SMALLINT       NOT NULL,
    JoinedDate       DATE           NOT NULL,
    HomeBranchID     INT            NOT NULL CONSTRAINT FK_Customer_Branch REFERENCES dbo.Branch (BranchID)
);

CREATE TABLE dbo.Loan (
    LoanID             INT            NOT NULL CONSTRAINT PK_Loan PRIMARY KEY,
    CustomerID         INT            NOT NULL CONSTRAINT FK_Loan_Customer REFERENCES dbo.Customer (CustomerID),
    ProductCode        VARCHAR(10)    NOT NULL CONSTRAINT FK_Loan_Product REFERENCES dbo.Product (ProductCode),
    BranchID           INT            NOT NULL CONSTRAINT FK_Loan_Branch REFERENCES dbo.Branch (BranchID),
    OfficerID          INT            NOT NULL CONSTRAINT FK_Loan_LoanOfficer REFERENCES dbo.LoanOfficer (OfficerID),
    ApplicationDate    DATE           NOT NULL,
    OriginationDate    DATE           NOT NULL,
    Principal          DECIMAL(12,2)  NOT NULL,
    InterestRate       DECIMAL(5,2)   NOT NULL,
    TermMonths         SMALLINT       NOT NULL,
    MonthlyPayment     DECIMAL(12,2)  NOT NULL,
    MaturityDate       DATE           NOT NULL,
    LoanStatus         NVARCHAR(20)   NOT NULL,
    OutstandingBalance DECIMAL(12,2)  NOT NULL
);

CREATE TABLE dbo.Payment (
    PaymentID         INT            NOT NULL CONSTRAINT PK_Payment PRIMARY KEY,
    LoanID            INT            NOT NULL CONSTRAINT FK_Payment_Loan REFERENCES dbo.Loan (LoanID),
    InstalmentNumber  SMALLINT       NOT NULL,
    DueDate           DATE           NOT NULL,
    AmountDue         DECIMAL(12,2)  NOT NULL,
    PaidDate          DATE           NULL,
    AmountPaid        DECIMAL(12,2)  NOT NULL,
    DaysLate          SMALLINT       NULL
);

CREATE TABLE dbo.Collateral (
    CollateralID     INT            NOT NULL CONSTRAINT PK_Collateral PRIMARY KEY,
    LoanID           INT            NOT NULL CONSTRAINT FK_Collateral_Loan REFERENCES dbo.Loan (LoanID),
    CollateralType   NVARCHAR(30)   NOT NULL,
    Description      NVARCHAR(100)  NOT NULL,
    ValuationAmount  DECIMAL(12,2)  NOT NULL,
    ValuationDate    DATE           NOT NULL
);

CREATE TABLE dbo.CreditRating (
    RatingID             INT           NOT NULL CONSTRAINT PK_CreditRating PRIMARY KEY,
    CustomerID           INT           NOT NULL CONSTRAINT FK_CreditRating_Customer REFERENCES dbo.Customer (CustomerID),
    RatingDate           DATE          NOT NULL,
    CreditScore          SMALLINT      NOT NULL,
    Grade                CHAR(1)       NOT NULL,
    ProbabilityOfDefault DECIMAL(6,4)  NOT NULL
);
GO
