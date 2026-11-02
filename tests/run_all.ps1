# SQL Server from Zero — run every script on your local SQL Server (Windows)
# and write tests\output\REPORT.md listing every error by script.
# Usage, from the repository root, in PowerShell:
#   .\tests\run_all.ps1                      # Windows authentication, server localhost
#   .\tests\run_all.ps1 -Server "localhost,1433" -User sa -Password "<YourPassword>"
param([string]$Server = "localhost", [string]$User = "", [string]$Password = "")
$ErrorActionPreference = "Continue"
$Root = Split-Path $PSScriptRoot -Parent
$Out = Join-Path $Root "tests\output"
Remove-Item $Out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$Out\logs" | Out-Null
$Data = "C:\NorthbridgeData"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
Copy-Item "$Root\data\csv\*.csv" $Data -Force
$auth = if ($User) { @("-U", $User, "-P", $Password) } else { @("-E") }

function Run-Sql($file, $log) {
  & sqlcmd -S $Server @auth -C -I -x -d master -i $file *> $log
}
function Rebuild {
  foreach ($s in "01_create_database","02_create_tables","03_load_data") {
    Run-Sql "$Root\sql\setup\$s.sql" "$Out\logs\setup_$s.log"
  }
}
function Bcp-Files {
  Remove-Item "$Data\*_rejected.txt*" -ErrorAction SilentlyContinue
  $a = if ($User) { @("-U", $User, "-P", $Password) } else { @("-T") }
  & sqlcmd -S $Server @auth -C -d NorthbridgeLending -Q "IF OBJECT_ID(N'dbo.Stage_Payment') IS NULL SELECT * INTO dbo.Stage_Payment FROM dbo.Payment WHERE 1 = 0;" *>> "$Out\logs\bcp.log"
  & bcp NorthbridgeLending.dbo.Stage_Payment format nul -c "-t," -f "$Data\Payment.fmt" -S $Server @a -u *>> "$Out\logs\bcp.log"
  & bcp NorthbridgeLending.dbo.Branch out "$Data\Branch_out.csv" -c "-t," -S $Server @a -u *>> "$Out\logs\bcp.log"
  & bcp "SELECT * FROM NorthbridgeLending.dbo.Product ORDER BY ProductCode" queryout "$Data\Product_out.csv" -c "-t," -S $Server @a -u *>> "$Out\logs\bcp.log"
}
$allowed = @{}
Get-Content "$Root\tests\expected_messages.txt" | ForEach-Object {
  $p = $_ -split ' '; $allowed[$p[0]] = $p[1..($p.Length-1)]
}
$report = @("# SQL Server from Zero — test run", "", "| Script | Errors (level 11+) | Expected messages | First error |", "|---|---:|---:|---|")
$total = 0
function Run-One($f) {
  $name = $f.BaseName; $ch = $name.Substring(2,2)
  Write-Host "Running $name ..."
  Run-Sql $f.FullName "$Out\logs\$name.log"
  $lines = Get-Content "$Out\logs\$name.log"
  $errs = @($lines | Where-Object { $_ -match '^Msg (\d+), Level 1[1-9]' })
  $ok = if ($allowed.ContainsKey($ch)) { $allowed[$ch] } else { @() }
  $exp = @($errs | Where-Object { ($_ -replace '^Msg (\d+),.*','$1') -in $ok }).Count
  $bad = @($errs | Where-Object { ($_ -replace '^Msg (\d+),.*','$1') -notin $ok })
  $first = ""
  if ($bad.Count -gt 0) { $i = [array]::IndexOf($lines, $bad[0]); $first = "$($bad[0]) - $($lines[$i+1])" }
  $script:total += $bad.Count
  $script:report += "| $name | $($bad.Count) | $exp | $($first -replace '\|','/') |"
}
# As a reader does: rebuild, run the chapter's examples, then its corrections.
foreach ($chap in Get-ChildItem "$Root\sql\chapters\ch*.sql") {
  $ch = $chap.BaseName.Substring(2,2)
  Rebuild
  if ($ch -eq "15") { Bcp-Files }
  Run-One $chap
  foreach ($sol in Get-ChildItem "$Root\sql\solutions\ch${ch}_*_solutions.sql") {
    if ($ch -eq "15") { Bcp-Files }
    Run-One $sol
  }
}
$report += "", "**Unexpected errors in total: $total**"
$report | Set-Content "$Out\REPORT.md" -Encoding UTF8
$report | Write-Host
