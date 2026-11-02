# SQL Server from Zero — companion repository

Material for the book **SQL Server from Zero: Every Command Explained Step by Step for Absolute Beginners** by Mohamed Miled.

Everything you need to follow the book: the Northbridge Lending dataset (CSV, Excel and SQL), every example of every chapter, and every correction of every exercise.

## Requirements

- SQL Server 2025 Enterprise Developer Edition (free for learning and testing) or SQL Server 2022. Every script runs on both.
- SQL Server Management Studio 22 (Windows), or Visual Studio Code with the SQL Server (mssql) extension (macOS, Linux).
- On macOS and Linux, run SQL Server in Docker:

```bash
docker run --platform linux/amd64 -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=<YourStrong#Password1>" \
  -p 1433:1433 --name northbridge-sql -d mcr.microsoft.com/mssql/server:2025-latest
```

## Build the database

Open and run the three setup scripts **in this order**:

1. `sql/setup/01_create_database.sql` — creates `NorthbridgeLending` (and deletes any earlier copy)
2. `sql/setup/02_create_tables.sql` — creates the eight tables with their keys
3. `sql/setup/03_load_data.sql` — loads 24,265 rows and prints a row count per table

Run the three scripts again at any time to reset the database to its original state.

Expected row counts:

| Table | Rows |
|---|---:|
| Branch | 8 |
| LoanOfficer | 24 |
| Product | 8 |
| Customer | 500 |
| Loan | 800 |
| Payment | 18,418 |
| Collateral | 550 |
| CreditRating | 3,957 |

## Contents

```text
data/csv/                 one CSV file per table (UTF-8, comma-separated, header row, ISO dates)
data/excel/               NorthbridgeLending.xlsx: README sheet + one sheet per table
sql/setup/                the three scripts that build the database
sql/chapters/             chNN_<topic>.sql: every example of chapter NN, in the order of the book
sql/solutions/            chNN_<topic>_solutions.sql: every correction of chapter NN, commented
```

## The dataset

Northbridge Lending is a fictional UK lender: 8 branches, 24 loan officers, 8 loan products, 500 customers, 800 loans (mortgages, personal, car and small-business loans), the monthly payment history of every loan, the collateral of secured loans and a six-monthly internal credit rating of every customer. Snapshot date: 30 September 2026. Amounts in GBP. All people, email addresses and telephone numbers are invented.

| Table | One row is… | Primary key |
|---|---|---|
| Branch | a branch | BranchID |
| LoanOfficer | an employee who arranges loans | OfficerID |
| Product | a loan product | ProductCode |
| Customer | a borrower | CustomerID |
| Loan | a loan | LoanID |
| Payment | a monthly instalment due | PaymentID |
| Collateral | an asset securing a loan | CollateralID |
| CreditRating | a credit assessment of a customer | RatingID |

## How to use the scripts

- Type the examples yourself first; open the chapter script to check a statement that does not work.
- Try every exercise before opening its solution.
- Scripts that change data end with a clean-up block. If your results differ from the book's, rebuild the database with the three setup scripts.
- Chapter 15 loads the CSV files with `BULK INSERT`: copy `data/csv` to `C:\NorthbridgeData\` on Windows, or into the container with `docker cp` (see the chapter).

## Test every script

`tests/` runs every chapter and solutions script on a real SQL Server and writes `tests/output/REPORT.md`, which lists the errors of each script. Before each script, the runner rebuilds the database so that every script starts from the original data.

- macOS or Linux, with Docker: `bash tests/run_all.sh`. It starts its own SQL Server 2025 container on port 14333.
- Windows, with SQL Server installed: `.\tests\run_all.ps1`. It needs `sqlcmd` and `bcp` and copies the CSV files to `C:\NorthbridgeData\`.
- GitHub: every push runs `.github/workflows/run-sql.yml`. The report appears on the run's summary page, and the full logs are attached to the run.

## Licence

The SQL scripts may be used freely in your own work. The dataset is fictional and may be used for teaching. The book text is © 2026 Mohamed Miled.
