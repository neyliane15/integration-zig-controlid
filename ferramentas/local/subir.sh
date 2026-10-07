#!/usr/bin/env bash
# Sobe o ambiente local completo (contrato §15.2): Postgres 16 + migrações + carga demo + PostgREST + portão (54321).
#
#   ferramentas/local/subir.sh             # sobe (mantém os dados se o banco mdg_local já existir; reaplica migrações)
#   ferramentas/local/subir.sh --recriar   # apaga e recria o banco mdg_local com a carga de demonstração
#   ferramentas/local/subir.sh --parar     # para PostgREST e portão (o Postgres continua)
#
# Grava .env.local (VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY, VITE_LOGIN_GOOGLE=false) e imprime a service_role key.
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$AQUI/../.." && pwd)"
BASE="${MDG_PG_DIR:-${TMPDIR:-/tmp}/mdg-postgres}"
export PGHOST="${PGHOST:-$BASE/socket}" PGPORT="${PGPORT:-${MDG_PG_PORTA:-54329}}" PGUSER="${PGUSER:-postgres}"
BANCO="${MDG_LOCAL_BANCO:-mdg_local}"
PORTA_PORTAO="${MDG_PORTA_PORTAO:-54321}"
PORTA_POSTGREST="${MDG_PORTA_POSTGREST:-54323}"
VERSAO_POSTGREST="v12.2.3"
export MDG_JWT_SEGREDO="${MDG_JWT_SEGREDO:-segredo-local-do-meu-dia-de-gerente-nao-use-em-producao}"
export MDG_PORTA_PORTAO="$PORTA_PORTAO" MDG_POSTGREST_URL="http://127.0.0.1:$PORTA_POSTGREST"
RUN="$BASE/run"
mkdir -p "$RUN"

parar() {
  for nome in portao postgrest; do
    if [ -f "$RUN/$nome.pid" ]; then
      kill "$(cat "$RUN/$nome.pid")" 2> /dev/null || true
      rm -f "$RUN/$nome.pid"
    fi
  done
}

if [ "${1:-}" = "--parar" ]; then
  parar
  echo "PostgREST e portão parados."
  exit 0
fi

# ------------------------------------------------------------------------------- Postgres + banco
"$RAIZ/supabase/testes/preparar-postgres.sh" > /dev/null
existe="$(psql -X -Atqd postgres -c "select 1 from pg_database where datname = '$BANCO'")"
if [ "${1:-}" = "--recriar" ] || [ "$existe" != "1" ]; then
  echo "criando o banco $BANCO (migrações + carga de demonstração)…"
  MDG_PG_BANCO="$BANCO" "$RAIZ/supabase/testes/executar.sh" --sem-testes > /dev/null
else
  echo "banco $BANCO existente: reaplicando migrações (idempotentes)…"
  for m in "$RAIZ"/supabase/migrations/*.sql; do
    PGOPTIONS='-c client_min_messages=warning' psql -X -q -v ON_ERROR_STOP=1 -d "$BANCO" -f "$m" > /dev/null
  done
fi
PGOPTIONS='-c client_min_messages=warning' psql -X -q -v ON_ERROR_STOP=1 -d "$BANCO" -f "$AQUI/preparar.sql" > /dev/null

# ----------------------------------------------------------------------------------- PostgREST
POSTGREST_BIN="$(command -v postgrest || true)"
if [ -z "$POSTGREST_BIN" ] && [ -x "$BASE/bin/postgrest" ]; then POSTGREST_BIN="$BASE/bin/postgrest"; fi
if [ -z "$POSTGREST_BIN" ]; then
  echo "PostgREST não encontrado no PATH; baixando $VERSAO_POSTGREST para $BASE/bin…"
  mkdir -p "$BASE/bin"
  ARQ="postgrest-$VERSAO_POSTGREST-linux-static-x64.tar.xz"
  if curl -fsSL -o "$BASE/bin/$ARQ" "https://github.com/PostgREST/postgrest/releases/download/$VERSAO_POSTGREST/$ARQ" \
     && tar -xJf "$BASE/bin/$ARQ" -C "$BASE/bin"; then
    rm -f "$BASE/bin/$ARQ"
    POSTGREST_BIN="$BASE/bin/postgrest"
  else
    cat >&2 <<MSG
Não consegui baixar o PostgREST. Instale manualmente e rode de novo:
  https://github.com/PostgREST/postgrest/releases  (binário "linux-static-x64", coloque no PATH)
  ou: brew install postgrest  /  apt install postgrest (versão >= 12)
MSG
    exit 1
  fi
fi

parar
cat > "$RUN/postgrest.conf" <<CONF
db-uri = "postgresql:///$BANCO?host=$PGHOST&port=$PGPORT&user=authenticator&password=authenticator"
db-schemas = "public, local_auth"
db-anon-role = "anon"
db-extra-search-path = "public, extensions"
db-pool = 10
jwt-secret = "$MDG_JWT_SEGREDO"
server-host = "127.0.0.1"
server-port = $PORTA_POSTGREST
log-level = "warn"
CONF
nohup "$POSTGREST_BIN" "$RUN/postgrest.conf" > "$BASE/postgrest.log" 2>&1 &
echo $! > "$RUN/postgrest.pid"

# ------------------------------------------------------------------------------------- portão
nohup node "$AQUI/portao.mjs" > "$BASE/portao.log" 2>&1 &
echo $! > "$RUN/portao.pid"

for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:$PORTA_POSTGREST/" > /dev/null 2>&1 \
     && curl -fsS "http://127.0.0.1:$PORTA_PORTAO/auth/v1/health" > /dev/null 2>&1; then
    pronto=1
    break
  fi
  sleep 0.5
done
if [ "${pronto:-0}" != "1" ]; then
  echo "Falha ao subir PostgREST/portão. Logs:" >&2
  tail -n 20 "$BASE/postgrest.log" "$BASE/portao.log" >&2
  exit 1
fi

CHAVES="$(node "$AQUI/portao.mjs" --chaves)"
ANON="$(node -e 'console.log(JSON.parse(process.argv[1]).anon)' "$CHAVES")"
SERVICO="$(node -e 'console.log(JSON.parse(process.argv[1]).service_role)' "$CHAVES")"

cat > "$RAIZ/.env.local" <<ENV
# Gerado por ferramentas/local/subir.sh — ambiente local (não versionar).
VITE_SUPABASE_URL=http://127.0.0.1:$PORTA_PORTAO
VITE_SUPABASE_ANON_KEY=$ANON
VITE_LOGIN_GOOGLE=false
ENV

cat <<FIM

Ambiente local no ar.
  Supabase (portão):  http://127.0.0.1:$PORTA_PORTAO   (auth em /auth/v1, API em /rest/v1)
  PostgREST direto:   http://127.0.0.1:$PORTA_POSTGREST
  Banco:              psql "host=$PGHOST port=$PGPORT user=postgres dbname=$BANCO"
  .env.local gravado (front: npm run dev → http://127.0.0.1:5173)
  Usuários demo (senha gerente123): master@meudiadegerente.app, admin@barbossanova.com.br,
    gerente@barbossanova.com.br, leitura@barbossanova.com.br, admin@cantinaroma.com.br

  anon key:          $ANON
  service_role key:  $SERVICO
  (N8N local: SUPABASE_URL=http://127.0.0.1:$PORTA_PORTAO  SUPABASE_SERVICE_ROLE_KEY=<service_role key>)

Parar: ferramentas/local/subir.sh --parar   ·   Logs: $BASE/postgrest.log, $BASE/portao.log
FIM
