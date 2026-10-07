#!/usr/bin/env bash
# Gera supabase/instalar.sql = todas as migrações de supabase/migrations/ em ordem, numa transação.
# Uso: ferramentas/gerar-instalar.sh   (ou npm run sql:instalar)
# Verificar num banco limpo: ferramentas/gerar-instalar.sh --verificar  (usa o Postgres de supabase/testes)
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAIDA="$RAIZ/supabase/instalar.sql"

shopt -s nullglob
MIGRACOES=("$RAIZ"/supabase/migrations/*.sql)
if [ "${#MIGRACOES[@]}" -eq 0 ]; then
  echo "Nenhuma migração em supabase/migrations." >&2
  exit 1
fi

{
  cat <<'CAB'
-- =====================================================================================================
-- Meu Dia de Gerente — instalação/atualização completa do banco (Supabase).
-- ARQUIVO GERADO por ferramentas/gerar-instalar.sh a partir de supabase/migrations/. NÃO EDITE À MÃO.
--
-- Como usar: Supabase → SQL Editor → cole este arquivo inteiro → Run.
-- É idempotente: rodar de novo atualiza funções/políticas sem perder dados.
-- Depois: supabase/README.md (criar o master, ligar o Google, carga de demonstração opcional).
-- =====================================================================================================
CAB
  echo
  echo "begin;"
  echo
  for m in "${MIGRACOES[@]}"; do
    echo "-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> $(basename "$m")"
    cat "$m"
    echo
    echo "-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de $(basename "$m")"
    echo
  done
  echo "commit;"
} > "$SAIDA"

echo "gerado: ${SAIDA#$RAIZ/} (${#MIGRACOES[@]} migrações)"

if [ "${1:-}" = "--verificar" ]; then
  BASE="${MDG_PG_DIR:-${TMPDIR:-/tmp}/mdg-postgres}"
  "$RAIZ/supabase/testes/preparar-postgres.sh" > /dev/null
  export PGHOST="${PGHOST:-$BASE/socket}" PGPORT="${PGPORT:-${MDG_PG_PORTA:-54329}}" PGUSER="${PGUSER:-postgres}"
  BANCO="mdg_instalar_$$"
  trap 'psql -X -q -d postgres -c "drop database if exists $BANCO with (force)" > /dev/null 2>&1 || true' EXIT
  psql -X -q -d postgres -c "create database $BANCO" > /dev/null
  export PGOPTIONS='-c client_min_messages=warning'
  psql -X -q -v ON_ERROR_STOP=1 -d "$BANCO" -f "$RAIZ/supabase/testes/00_ambiente_supabase.sql" > /dev/null
  psql -X -q -v ON_ERROR_STOP=1 -d "$BANCO" -f "$SAIDA" > /dev/null
  psql -X -q -v ON_ERROR_STOP=1 -d "$BANCO" -f "$SAIDA" > /dev/null
  psql -X -q -v ON_ERROR_STOP=1 -d "$BANCO" -f "$RAIZ/supabase/testes/90_auditoria.sql" > /dev/null
  echo "verificado: instala num banco limpo, reinstala sem erro e passa na auditoria"
fi
