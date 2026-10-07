# Ambiente local completo

Sobe na sua máquina tudo o que o front e o N8N precisam do Supabase, sem conta no Supabase:

```
Postgres 16 (socket, porta 54329)  ←  PostgREST (127.0.0.1:54323)  ←  portão (127.0.0.1:54321)  ←  front / N8N
```

```bash
npm run local                          # = ferramentas/local/subir.sh
ferramentas/local/subir.sh --recriar   # apaga e recria o banco mdg_local com a carga de demonstração
ferramentas/local/subir.sh --parar     # para PostgREST e portão (o Postgres continua)
```

Requisitos: Postgres 16 em `/usr/lib/postgresql/16/bin` (ou `MDG_PG_BIN`), Node ≥ 22, `curl`. O PostgREST (v12) é usado
do `PATH`; se não houver, o script baixa o binário estático para `${TMPDIR:-/tmp}/mdg-postgres/bin`.

O que o `subir.sh` faz:
1. `supabase/testes/preparar-postgres.sh` (cluster descartável) e o banco `mdg_local`: na primeira vez (ou `--recriar`)
   aplica `00_ambiente_supabase.sql` + migrações + `supabase/seed/*.sql`; depois só reaplica as migrações (mantém os dados).
2. `preparar.sql`: schema `local_auth` (só service_role) com as funções que o portão usa para conferir a senha bcrypt de
   `auth.users`, cadastrar e trocar senha.
3. Sobe o PostgREST (`db-schemas = public, local_auth`, JWT HS256 com o segredo local) e o `portao.mjs`.
4. Grava `.env.local` na raiz (`VITE_SUPABASE_URL=http://127.0.0.1:54321`, `VITE_SUPABASE_ANON_KEY`, `VITE_LOGIN_GOOGLE=false`)
   e imprime a **service_role key** (para o N8N local: `SUPABASE_URL=http://127.0.0.1:54321`).

## Portão (`portao.mjs`)
Imita do Supabase só o necessário:

| rota | comportamento |
|---|---|
| `POST /auth/v1/token?grant_type=password` | confere e-mail/senha (bcrypt) e devolve sessão (JWT de 1 h + refresh token) |
| `POST /auth/v1/token?grant_type=refresh_token` | renova a sessão |
| `GET/PUT /auth/v1/user` | usuário atual / troca de senha e metadados (`updateUser`) |
| `POST /auth/v1/signup` | cria a conta já confirmada e devolve sessão (o gatilho cria o perfil sem empresa) |
| `POST /auth/v1/recover` | só registra no log (nenhum e-mail é enviado) |
| `POST /auth/v1/logout`, `GET /auth/v1/health`, `GET /auth/v1/settings` | ok |
| `/rest/v1/*` | repassado ao PostgREST (sem `Authorization`, o `apikey` vale como token) |
| `/storage/v1/*` | **501** — o Storage não existe localmente (upload de foto facial só no Supabase) |

CORS liberado para qualquer origem. `node ferramentas/local/portao.mjs --chaves` imprime as chaves anon/service_role.

Variáveis: `MDG_JWT_SEGREDO` (segredo HS256; padrão local fixo), `MDG_PORTA_PORTAO` (54321), `MDG_PORTA_POSTGREST` (54323),
`MDG_LOCAL_BANCO` (`mdg_local`), `MDG_PG_DIR`, `MDG_PG_PORTA`.

Usuários da demonstração (senha `gerente123`): `master@meudiadegerente.app`, `admin@barbossanova.com.br`,
`gerente@barbossanova.com.br`, `leitura@barbossanova.com.br`, `admin@cantinaroma.com.br`.

Logs: `${TMPDIR:-/tmp}/mdg-postgres/postgrest.log` e `portao.log`. Banco:
`psql "host=${TMPDIR:-/tmp}/mdg-postgres/socket port=54329 user=postgres dbname=mdg_local"`.

> Somente desenvolvimento: o segredo JWT, a senha do `authenticator` e o `local_auth` nunca vão para o Supabase.
