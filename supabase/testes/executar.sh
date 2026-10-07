#!/usr/bin/env bash
# Testes de banco do Meu Dia de Gerente.
# Recria o banco, aplica 00_ambiente_supabase.sql, as migrações, a carga (seed/*.sql), as migrações DE NOVO (idempotência)
# e roda os testes NN_*.sql (NN >= 10) em ordem. Para no primeiro erro; termina com "tudo passou".
#
# Uso:
#   supabase/testes/executar.sh                 # tudo
#   supabase/testes/executar.sh 14 16           # só os testes cujo nome começa com 14 ou 16 (o banco é montado igual)
#   supabase/testes/executar.sh --sem-testes    # só monta o banco (usado por ferramentas/local/subir.sh)
#
# Variáveis: PGHOST (padrão: socket de preparar-postgres.sh), PGPORT (54329), PGUSER (postgres),
#            MDG_PG_BANCO (padrão: mdg_teste_<pid>, apagado no fim; MDG_MANTER_BANCO=1 mantém),
#            MDG_SEM_SEED=1 (não aplica seed/).
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$AQUI/../.." && pwd)"
BASE="${MDG_PG_DIR:-${TMPDIR:-/tmp}/mdg-postgres}"

export PGHOST="${PGHOST:-$BASE/socket}"
export PGPORT="${PGPORT:-${MDG_PG_PORTA:-54329}}"
export PGUSER="${PGUSER:-postgres}"
# Sem MDG_PG_BANCO: banco único por execução (execuções em paralelo não colidem), apagado no fim.
if [ -n "${MDG_PG_BANCO:-}" ]; then
  BANCO="$MDG_PG_BANCO"; TEMPORARIO=0
else
  BANCO="mdg_teste_$$"; TEMPORARIO=1
fi

SEM_TESTES=0
FILTROS=()
for arg in "$@"; do
  case "$arg" in
    --sem-testes) SEM_TESTES=1 ;;
    *) FILTROS+=("$arg") ;;
  esac
done

if ! psql -X -d postgres -Atqc 'select 1' > /dev/null 2>&1; then
  echo "Postgres não está acessível em $PGHOST:$PGPORT. Rode antes: supabase/testes/preparar-postgres.sh" >&2
  exit 1
fi

SAIDA="$(mktemp)"
limpar() {
  rm -f "$SAIDA"
  if [ "$TEMPORARIO" = "1" ] && [ -z "${MDG_MANTER_BANCO:-}" ]; then
    PGOPTIONS="-c client_min_messages=warning" psql -X -q -d postgres -c "drop database if exists $BANCO with (force)" > /dev/null 2>&1 || true
  fi
}
trap limpar EXIT

# Aplica um arquivo SQL; em erro mostra a saída e para.
aplicar() {
  local arquivo="$1"
  if ! PGOPTIONS='-c client_min_messages=warning' psql -X -q -v ON_ERROR_STOP=1 -d "$BANCO" -f "$arquivo" > "$SAIDA" 2>&1; then
    echo "ERRO ao aplicar ${arquivo#$RAIZ/}:" >&2
    cat "$SAIDA" >&2
    exit 1
  fi
  if grep -q 'WARNING' "$SAIDA"; then
    grep 'WARNING' "$SAIDA" | sed "s|^|  [${arquivo#$RAIZ/}] |" >&2
  fi
}

PGOPTIONS="-c client_min_messages=warning" psql -X -q -d postgres -c "drop database if exists $BANCO with (force)" > /dev/null
psql -X -q -d postgres -c "create database $BANCO" > /dev/null

echo "banco $BANCO recriado ($PGHOST)"
aplicar "$AQUI/00_ambiente_supabase.sql"

shopt -s nullglob
MIGRACOES=("$RAIZ"/supabase/migrations/*.sql)
SEEDS=("$RAIZ"/supabase/seed/*.sql)

for m in "${MIGRACOES[@]}"; do aplicar "$m"; done
echo "migrações aplicadas (${#MIGRACOES[@]})"
if [ "${MDG_SEM_SEED:-0}" != "1" ]; then
  for s in "${SEEDS[@]}"; do aplicar "$s"; done
  echo "carga aplicada (${#SEEDS[@]})"
fi
for m in "${MIGRACOES[@]}"; do aplicar "$m"; done
echo "migrações reaplicadas (idempotência ok)"

if [ "$SEM_TESTES" = "1" ]; then
  exit 0
fi

TOTAL=0
for t in "$AQUI"/[0-9][0-9]_*.sql; do
  nome="$(basename "$t")"
  nn="${nome:0:2}"
  [ "$((10#$nn))" -ge 10 ] || continue
  if [ "${#FILTROS[@]}" -gt 0 ]; then
    casou=0
    for f in "${FILTROS[@]}"; do [[ "$nome" == "$f"* ]] && casou=1; done
    [ "$casou" = "1" ] || continue
  fi
  if ! psql -X -q -v ON_ERROR_STOP=1 -d "$BANCO" -f "$t" 2> "$SAIDA" > /dev/null; then
    echo "FALHOU: $nome" >&2
    grep -v '^NOTICE:  ok' "$SAIDA" | tail -n 40 >&2
    exit 1
  fi
  n="$(grep -c 'NOTICE:  ok' "$SAIDA" || true)"
  TOTAL=$((TOTAL + n))
  printf '  %-32s %4s verificações\n' "$nome" "$n"
done

echo "tudo passou ($TOTAL verificações)"
