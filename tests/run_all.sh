#!/usr/bin/env bash
# SQL Server from Zero — run every script of the repository on a real SQL Server 2025
# in Docker and write a report of every error, by chapter and line.
#
# Usage (macOS, Linux, or GitHub Actions), from the repository root:
#   bash tests/run_all.sh
# Requirements: Docker. The script starts its own container "northbridge-test",
# listening on port 14333, and removes it at the end (KEEP=1 keeps it).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/tests/output"
C=northbridge-test
PW="${SA_PASSWORD:-Northbridge#Test2026}"
IMAGE="${IMAGE:-mcr.microsoft.com/mssql/server:2025-latest}"
IMPORT=/var/opt/mssql/data/import
rm -rf "$OUT"; mkdir -p "$OUT/logs" "$OUT/work"

echo "Starting $IMAGE ..."
docker rm -f $C >/dev/null 2>&1
docker run -d --platform linux/amd64 --name $C -e ACCEPT_EULA=Y -e "MSSQL_SA_PASSWORD=$PW" \
  -p 14333:1433 "$IMAGE" >/dev/null || { echo "docker run failed"; exit 2; }

TOOLS=""
for i in $(seq 1 90); do
  for t in /opt/mssql-tools18/bin /opt/mssql-tools/bin; do
    if docker exec $C test -x $t/sqlcmd 2>/dev/null; then TOOLS=$t; fi
  done
  if [ -n "$TOOLS" ] && docker exec $C $TOOLS/sqlcmd -S localhost -U sa -P "$PW" -C -Q "SELECT 1" >/dev/null 2>&1; then break; fi
  sleep 2
done
[ -n "$TOOLS" ] || { echo "sqlcmd not found in the image"; exit 2; }
docker exec $C $TOOLS/sqlcmd -S localhost -U sa -P "$PW" -C -h -1 -Q "SET NOCOUNT ON; SELECT @@VERSION" | head -1 | tee "$OUT/version.txt"

# Files the chapters expect: CSVs in the import folder.
docker exec -u 0 $C mkdir -p $IMPORT
docker cp "$ROOT/data/csv/." $C:$IMPORT/
docker exec -u 0 $C chown -R mssql $IMPORT

sql() {  # sql <file> <log>
  docker cp "$1" $C:/tmp/run.sql
  docker exec $C $TOOLS/sqlcmd -S localhost -U sa -P "$PW" -C -I -x -W -s"|" -d master -i /tmp/run.sql >"$2" 2>&1
}
adapt() {  # Windows paths -> container paths; CODEPAGE is Windows-only
  sed -e "s#C:\\\\NorthbridgeData\\\\#$IMPORT/#g" \
      -e "s#CODEPAGE = '65001'#FIELDQUOTE = '\"'#g" "$1" > "$2"
}
rebuild() {
  for s in 01_create_database 02_create_tables 03_load_data; do
    sql "$ROOT/sql/setup/$s.sql" "$OUT/logs/setup_$s.log"
  done
}
bcp_files() {  # the files chapter 15 creates with bcp at the command line
  docker exec $C sh -c "rm -f $IMPORT/*_rejected.txt*"
  # the format file is written from the staging table that chapter 15 creates in section 1
  docker exec $C $TOOLS/sqlcmd -S localhost -U sa -P "$PW" -C -d NorthbridgeLending -Q \
    "IF OBJECT_ID(N'dbo.Stage_Payment') IS NULL SELECT * INTO dbo.Stage_Payment FROM dbo.Payment WHERE 1 = 0;" >>"$OUT/logs/bcp.log" 2>&1
  docker exec $C $TOOLS/bcp NorthbridgeLending.dbo.Stage_Payment format /dev/null -c -t, -r "\r\n" \
    -f $IMPORT/Payment.fmt -S localhost -U sa -P "$PW" -u >>"$OUT/logs/bcp.log" 2>&1
  docker exec $C $TOOLS/bcp NorthbridgeLending.dbo.Branch out $IMPORT/Branch_out.csv -c -t, \
    -S localhost -U sa -P "$PW" -u >>"$OUT/logs/bcp.log" 2>&1
  docker exec $C $TOOLS/bcp "SELECT * FROM NorthbridgeLending.dbo.Product ORDER BY ProductCode" \
    queryout $IMPORT/Product_out.csv -c -t, -S localhost -U sa -P "$PW" -u >>"$OUT/logs/bcp.log" 2>&1
}

echo "Building the database ..."
rebuild
grep -E "^Msg [0-9]+, Level 1[1-9]" "$OUT"/logs/setup_*.log && { echo "SETUP FAILED"; }

REPORT="$OUT/REPORT.md"
{
  echo "# SQL Server from Zero — test run"
  echo; echo "Server: $(cat "$OUT/version.txt")"; echo; echo "Date: $(date -u '+%Y-%m-%d %H:%M UTC')"; echo
  echo "| Script | Errors (level 11+) | Expected messages | First error |"
  echo "|---|---:|---:|---|"
} > "$REPORT"
TOTAL=0
run_one() {  # run_one <script path>
  local f="$1" name ch allowed errs exp n first line text
  name=$(basename "$f" .sql); ch=${name:2:2}
  adapt "$f" "$OUT/work/$name.sql"
  echo "Running $name ..."
  sql "$OUT/work/$name.sql" "$OUT/logs/$name.log"
  allowed=$(grep -E "^$ch " "$ROOT/tests/expected_messages.txt" 2>/dev/null | cut -d' ' -f2- | tr ' ' '|')
  errs=$(grep -E "^Msg [0-9]+, Level 1[1-9]|Sqlcmd: Error|Invalid cursor state" "$OUT/logs/$name.log" || true)
  exp=0
  if [ -n "$allowed" ]; then
    exp=$(printf '%s\n' "$errs" | grep -cE "^Msg ($allowed)," || true)
    errs=$(printf '%s\n' "$errs" | grep -vE "^Msg ($allowed)," || true)
  fi
  n=$(printf '%s' "$errs" | grep -c "^Msg" || true)
  first=""
  if [ "$n" -gt 0 ]; then
    line=$(printf '%s\n' "$errs" | head -1)
    text=$(grep -A1 -F "$line" "$OUT/logs/$name.log" | sed -n 2p | cut -c1-120)
    first="$line — $text"
  fi
  TOTAL=$((TOTAL + n))
  echo "| $name | $n | $exp | ${first//|//} |" >> "$REPORT"
}
# As a reader does: rebuild, run the chapter's examples, then its corrections.
for chap in "$ROOT"/sql/chapters/ch*.sql; do
  ch=$(basename "$chap" | cut -c3-4)
  rebuild
  if [ "$ch" = "15" ]; then              # chapter 15 needs its tables before bcp
    bcp_files
  fi
  run_one "$chap"
  for sol in "$ROOT"/sql/solutions/ch${ch}_*_solutions.sql; do
    [ "$ch" = "15" ] && bcp_files
    run_one "$sol"
  done
done
{ echo; echo "**Unexpected errors in total: $TOTAL**"; echo
  echo "## Error details"; echo
  for lg in "$OUT"/logs/ch*.log; do
    case "$lg" in *prepass*) continue;; esac
    if grep -qE "^Msg [0-9]+, Level 1[1-9]|Sqlcmd: Error" "$lg"; then
      echo "### $(basename "$lg" .log)"; echo '```'
      grep -E -A8 "^Msg [0-9]+, Level 1[1-9]|Sqlcmd: Error" "$lg" | grep -v "Bulk load data conversion" | head -40
      echo '```'; echo
    fi
  done
  echo "## bcp output"; echo '```'; cat "$OUT/logs/bcp.log" 2>/dev/null | head -40; echo '```'
  echo "Full output of every script: tests/output/logs/<script>.log (results included)."; } >> "$REPORT"
cat "$REPORT"
if [ "${FULL_LOGS:-0}" = "1" ]; then
  for lg in "$OUT"/logs/ch*.log; do echo "===== LOG $(basename "$lg" .log)"; cat "$lg"; done
fi
[ "${KEEP:-0}" = "1" ] || docker rm -f $C >/dev/null
[ "$TOTAL" -eq 0 ]
