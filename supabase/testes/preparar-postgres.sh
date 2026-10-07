#!/usr/bin/env bash
# Sobe (ou reaproveita) um cluster Postgres 16 descartável, só com socket local, para os testes de banco e o ambiente local.
# Idempotente: se o cluster já existe e está no ar, não faz nada. Imprime (stdout) o diretório do socket.
#
# Variáveis (todas opcionais):
#   MDG_PG_DIR    diretório do cluster (padrão: ${TMPDIR:-/tmp}/mdg-postgres)
#   MDG_PG_PORTA  porta (só nomeia o socket; não há TCP)   (padrão: 54329)
#   MDG_PG_BIN    binários do Postgres                      (padrão: /usr/lib/postgresql/16/bin)
#   MDG_PG_USUARIO_SO  usuário do SO dono do cluster quando rodando como root (padrão: postgres)
set -euo pipefail

BASE="${MDG_PG_DIR:-${TMPDIR:-/tmp}/mdg-postgres}"
PORTA="${MDG_PG_PORTA:-54329}"
BIN="${MDG_PG_BIN:-/usr/lib/postgresql/16/bin}"
DADOS="$BASE/dados"
SOCKET="$BASE/socket"
LOG="$BASE/postgres.log"

if [ ! -x "$BIN/initdb" ]; then
  echo "Postgres 16 não encontrado em $BIN (defina MDG_PG_BIN)." >&2
  exit 1
fi

# Postgres não roda como root: usa um usuário de SO dedicado.
if [ "$(id -u)" = "0" ]; then
  USUARIO_SO="${MDG_PG_USUARIO_SO:-postgres}"
  if ! id "$USUARIO_SO" > /dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$USUARIO_SO"
  fi
  como() { runuser -u "$USUARIO_SO" -- "$@"; }
  mkdir -p "$BASE"
  chown "$USUARIO_SO" "$BASE"
  chmod 755 "$BASE"
else
  como() { "$@"; }
  mkdir -p "$BASE"
fi

como mkdir -p "$SOCKET"

if [ ! -f "$DADOS/PG_VERSION" ]; then
  como "$BIN/initdb" -D "$DADOS" -U postgres --auth=trust --encoding=UTF8 --locale=C > "$BASE/initdb.log" 2>&1 \
    || { cat "$BASE/initdb.log" >&2; exit 1; }
  como tee -a "$DADOS/postgresql.conf" > /dev/null <<EOF

# --- Meu Dia de Gerente: cluster descartável de testes ---
listen_addresses = ''
unix_socket_directories = '$SOCKET'
port = $PORTA
timezone = 'UTC'
fsync = off
synchronous_commit = off
full_page_writes = off
max_connections = 50
EOF
fi

if ! como "$BIN/pg_ctl" -D "$DADOS" status > /dev/null 2>&1; then
  como "$BIN/pg_ctl" -D "$DADOS" -l "$LOG" -w -t 60 start > /dev/null \
    || { tail -n 30 "$LOG" >&2; exit 1; }
fi

chmod 755 "$SOCKET" 2> /dev/null || true
echo "$SOCKET"
