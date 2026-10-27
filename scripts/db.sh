#!/usr/bin/env bash
# Kelola hidup/mati Supabase lokal project bengkel-pos — hanya saat dibutuhkan.
#
# Dipanggil dari Windows lewat scripts/db.ps1 (npm run db:up / db:down / ...).
# Menyalakan hanya layanan yang dipakai aplikasi (db, auth, rest, kong) supaya
# RAM WSL tetap kecil: realtime, storage, studio, inbucket, dll. di-exclude.
#
# Aturan project: hanya menyentuh container bernama *bengkel-pos*.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/supabase/config.toml"
ENV_FILE="$ROOT/.env.local"
RELAY_SCRIPT="$ROOT/scripts/wsl-port-relay.py"
START_LOG="/tmp/bengkel-supabase-start.log"
STOP_LOG="/tmp/bengkel-supabase-stop.log"
RELAY_LOG="/tmp/bengkel-relay.log"
EXCLUDES="realtime,storage-api,imgproxy,studio,mailpit,edge-runtime,logflare,vector,supavisor,postgres-meta"

ACTION="${1:-status}"

read_cfg() {
  awk -v sec="[$1]" -v key="$2" '
    { sub(/\r$/, "") }
    /^\[/ { insec = ($0 == sec); next }
    insec && $1 == key {
      sub(/^[^=]*=[ \t]*/, "")
      sub(/[ \t"#].*$/, "")
      print
      exit
    }
  ' "$CONFIG"
}

PROJECT_ID="$(awk -F'"' '/^project_id/ {print $2; exit}' "$CONFIG")"
API_PORT="$(read_cfg api port)"
RELAY_PORT="$(sed -n 's|^NEXT_PUBLIC_SUPABASE_URL="\?http://127\.0\.0\.1:\([0-9]\+\).*|\1|p' "$ENV_FILE" | head -1)"
RELAY_PORT="${RELAY_PORT:-56021}"
SB_VERSION="$(sed -n 's/.*"supabase": *"\^\?\([0-9][0-9.]*\)".*/\1/p' "$ROOT/package.json" | head -1)"
SB_VERSION="${SB_VERSION:-2.122.0}"

if [ -z "$PROJECT_ID" ] || [ -z "$API_PORT" ]; then
  echo "GAGAL: project_id / api.port tidak terbaca dari supabase/config.toml" >&2
  exit 1
fi

sb() { ( cd /tmp && npx --yes "supabase@$SB_VERSION" --workdir "$ROOT" "$@" ); }

api_ok() { curl -fsS -m 3 "http://127.0.0.1:$API_PORT/auth/v1/health" >/dev/null 2>&1; }
relay_ok() { curl -fsS -m 3 "http://127.0.0.1:$RELAY_PORT/auth/v1/health" >/dev/null 2>&1; }
containers_up() { docker ps --format '{{.Names}}' | grep -qx "supabase_db_$PROJECT_ID"; }

start_relay() {
  if relay_ok; then
    echo "relay   : sudah jalan di $RELAY_PORT"
    return 0
  fi
  nohup python3 "$RELAY_SCRIPT" "$RELAY_PORT" 127.0.0.1 "$API_PORT" >"$RELAY_LOG" 2>&1 &
  for _ in $(seq 1 20); do
    sleep 0.5
    if relay_ok; then
      echo "relay   : $RELAY_PORT -> 127.0.0.1:$API_PORT siap"
      return 0
    fi
  done
  echo "relay   : GAGAL start, lihat $RELAY_LOG" >&2
  return 1
}

stop_relay() {
  if pgrep -f "$RELAY_SCRIPT" >/dev/null 2>&1; then
    pkill -f "$RELAY_SCRIPT" || true
    echo "relay   : dimatikan"
  else
    echo "relay   : tidak jalan"
  fi
}

wait_api() {
  for _ in $(seq 1 60); do
    if api_ok; then return 0; fi
    sleep 1
  done
  return 1
}

do_up() {
  if api_ok; then
    echo "database: sudah hidup (port $API_PORT)"
  else
    echo "database: menyalakan $PROJECT_ID (tanpa realtime/storage/studio) ..."
    if ! sb start -x "$EXCLUDES" >"$START_LOG" 2>&1; then
      echo "database: GAGAL menyalakan. Log terakhir:" >&2
      tail -20 "$START_LOG" >&2
      return 1
    fi
    if ! wait_api; then
      echo "database: API belum sehat setelah 60 detik, lihat $START_LOG" >&2
      return 1
    fi
    echo "database: hidup (project $PROJECT_ID, api $API_PORT)"
  fi
  start_relay
  echo "siap    : http://127.0.0.1:$RELAY_PORT"
}

do_down() {
  stop_relay
  if containers_up; then
    echo "database: menghentikan $PROJECT_ID ..."
    if ! sb stop >"$STOP_LOG" 2>&1; then
      echo "database: GAGAL berhenti. Log terakhir:" >&2
      tail -20 "$STOP_LOG" >&2
      return 1
    fi
    echo "database: mati (data tetap tersimpan di volume)"
  else
    echo "database: sudah mati"
  fi
  echo "catatan : RAM Windows baru turun penuh setelah 'npm run wsl:off'"
}

do_status() {
  echo "project : $PROJECT_ID (CLI $SB_VERSION)"
  echo "api     : 127.0.0.1:$API_PORT"
  echo "relay   : 127.0.0.1:$RELAY_PORT"
  echo
  if containers_up; then
    local names
    names="$(docker ps --filter "name=$PROJECT_ID" --format '{{.Names}}')"
    echo "container:"
    # shellcheck disable=SC2086
    docker stats --no-stream --format '  {{.Name}}  {{.MemUsage}}  cpu {{.CPUPerc}}' $names
    echo
    echo "total RAM container: $(docker stats --no-stream --format '{{.MemUsage}}' $names \
      | awk -F'/' '{gsub(/[^0-9.]/,"",$1); s+=$1} END {printf "%.0f MiB", s}')"
  else
    echo "container: tidak ada yang jalan"
  fi
  echo "api sehat : $(api_ok && echo ya || echo tidak)"
  echo "relay     : $(relay_ok && echo ya || echo tidak)"
  echo
  echo "memori WSL:"
  free -h | awk 'NR==1 || NR==2 {print "  " $0}'
}

do_reset() {
  echo "database: reset $PROJECT_ID (migrasi + seed) ..."
  if ! sb db reset >"$START_LOG" 2>&1; then
    echo "database: GAGAL reset. Log terakhir:" >&2
    tail -20 "$START_LOG" >&2
    return 1
  fi
  if ! wait_api; then
    echo "database: API belum sehat setelah reset, lihat $START_LOG" >&2
    return 1
  fi
  echo "database: reset selesai"
  # Port yang dipublikasikan ulang butuh relay baru.
  stop_relay >/dev/null 2>&1 || true
  start_relay
}

case "$ACTION" in
  up) do_up ;;
  down) do_down ;;
  status) do_status ;;
  reset) do_reset ;;
  *)
    echo "pemakaian: db.sh {up|down|status|reset}" >&2
    exit 2
    ;;
esac
