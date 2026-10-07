# Banco (Supabase) — Meu Dia de Gerente

Tudo que precisa de privilégio é SQL (`security definer`) — não há Edge Functions. Instalar = rodar um arquivo SQL.

## Instalar ou atualizar no Supabase

1. Crie o projeto no Supabase (região São Paulo, de preferência).
2. **SQL Editor** → cole o conteúdo de [`instalar.sql`](instalar.sql) → **Run**.
   É idempotente: para atualizar uma instalação existente, rode a versão nova do arquivo do mesmo jeito.
3. Crie o master: [`instalacao/criar_master.sql`](instalacao/criar_master.sql) (escolha uma das opções).
4. **Authentication → Providers**: e-mail ligado. Para "Entrar com Google", ligue o provedor Google e use
   `VITE_LOGIN_GOOGLE=true` no front. Em **URL Configuration**, coloque a URL do front (Vercel) em *Site URL* e
   `https://SEU-FRONT/redefinir-senha` em *Redirect URLs*.
5. **Project Settings → API**: `VITE_SUPABASE_URL` e a chave `anon` vão para o front (`.env`/Vercel);
   a `service_role` vai **só** para o N8N (`SUPABASE_SERVICE_ROLE_KEY`). Nunca coloque a service_role no front.
6. Opcional: carga de demonstração ([`instalacao/carga_demo.sql`](instalacao/carga_demo.sql)).

O bucket privado `funcionarios-fotos` (fotos faciais para o iDFace) e suas políticas são criados pela própria instalação.

## Estrutura

| pasta/arquivo | o que é |
|---|---|
| `migrations/` | SQL idempotente, numerado por dono (contrato §4). `…0900_permissoes.sql` é sempre a última. |
| `instalar.sql` | **gerado** por `ferramentas/gerar-instalar.sh` (`npm run sql:instalar`): todas as migrações numa transação. Não edite à mão. |
| `seed/` | carga de demonstração (`10_demo_base.sql`, `20_demo_operacao.sql`), idempotente. |
| `testes/` | testes de banco (Postgres 16 local). |
| `instalacao/` | SQLs avulsos de instalação (criar master, carga demo). |

### Segurança — como os privilégios funcionam
- RLS ligada em **todas** as tabelas. Políticas usam as auxiliares `eh_master()`, `empresa_leitura()`, `empresa_operacao()`,
  `empresa_administracao()` (papéis do contrato §3).
- Cada objeto declara o acesso no `comment on` (`[api:crud]`, `[api:leitura]`, `[api:nenhum]`, `[api]`, `[politica]`,
  `[servico]`, `[interno]`). A migração `…0900_permissoes.sql` varre o catálogo e concede os privilégios — `anon` não recebe nada.
- Segredos das integrações (`integracoes_segredos`) e credenciais dos funcionários (`funcionario_credenciais`,
  `funcionario_cartoes`) não têm nenhum acesso para `authenticated`: o front só grava por RPC e pergunta o que está preenchido.
- As RPCs `ingestao_*` (`[servico]`) só aceitam a `service_role` (N8N).

## Testes de banco

```bash
npm run test:banco                    # sobe o Postgres 16 descartável e roda tudo
supabase/testes/executar.sh 14 19     # só os arquivos que começam com 14 ou 19 (o banco é montado igual)
```

- `testes/preparar-postgres.sh`: cluster descartável em `${TMPDIR:-/tmp}/mdg-postgres` (só socket, porta 54329,
  usuário de SO `postgres` quando rodando como root). Idempotente; imprime o diretório do socket.
- `testes/executar.sh`: cria um banco **único por execução** (`mdg_teste_<pid>`, apagado no fim — execuções paralelas não colidem),
  aplica `00_ambiente_supabase.sql`, as migrações, a carga, as migrações **de novo** (idempotência) e os testes `NN_*.sql`
  (NN ≥ 10) em ordem; para no primeiro erro; termina com `tudo passou`. `MDG_PG_BANCO=nome` fixa o banco e o mantém;
  `MDG_MANTER_BANCO=1` mantém o temporário; `--sem-testes` só monta o banco.
- `testes/00_ambiente_supabase.sql` imita o Supabase: papéis `anon`/`authenticated`/`service_role`/`authenticator`, schemas
  `auth` (users, identities, `auth.uid()`, `auth.role()`, `auth.jwt()`), `extensions` (pgcrypto) e `storage` mínimo, e os
  privilégios padrão. Ajudantes de teste no schema `teste`:

| função | uso |
|---|---|
| `teste.ok(descricao, condicao)` | afirmação (notice `ok:` ou exceção `FALHOU:`) |
| `teste.erro(descricao, sql, trecho_da_mensagem, sqlstate)` | exige que o SQL falhe com essa mensagem/código |
| `teste.passa(descricao, sql)` | exige que o SQL rode sem erro |
| `teste.contar(sql)` / `teste.afetadas(sql)` | nº de linhas lidas / afetadas por insert-update-delete (como o papel atual) |
| `teste.como(email)` / `teste.como(null)` | veste um usuário (role `authenticated` + claims) / `anon` |
| `teste.como_servico()` / `teste.como_dono()` | veste a `service_role` (N8N) / volta ao dono (SQL Editor, sem JWT) |
| `teste.uid(email)` | id do usuário (enxerga `auth.users` mesmo vestido de outro papel) |
| `teste.cenario_b1()` | cenário do backend-1: empresas E1/E2, usuários `b1.<papel><n>@teste.local`, funcionários, integrações |

  Cada arquivo roda em `begin; … rollback;`, não depende de outro e fixa o relógio com `set local app.agora = '…'`.
  Atenção: numa mesma instrução, uma subconsulta não enxerga o que uma função chamada ali alterou — separe em duas instruções.
- `testes/90_auditoria.sql` varre o catálogo inteiro: tabela sem etiqueta ou sem RLS, `security definer` sem `search_path`,
  FK sem índice, `empresa_id` sem índice inicial, privilégios divergentes da etiqueta, qualquer privilégio para `anon`.

## Ambiente local completo

`npm run local` (detalhes em [`../ferramentas/local/README.md`](../ferramentas/local/README.md)): Postgres + migrações + carga +
PostgREST + portão de auth em `http://127.0.0.1:54321`; grava `.env.local` para o front e imprime a service_role para o N8N.

## Convenções úteis para quem escreve SQL aqui
- Relógio de negócio: `agora()` (nunca `now()` direto); dia de trabalho: `dia_de_trabalho(instante, empresa)`,
  `dia_de_trabalho_instante(data, hora, empresa)` (horário de escala → instante, §2.4).
- Escopo de empresa: `resolver_empresa(p_empresa, 'ler'|'operar'|'administrar')`. `pode_ler/pode_operar/pode_administrar`
  devolvem boolean estrito (nunca null) e aceitam o "sistema" (`service_role` ou SQL Editor).
- Funções de gatilho que leem/escrevem outras tabelas devem ser `security definer` (o `authenticated` não executa funções `[interno]`).
- Depois de mudar migrações: `npm run test:banco` e `npm run sql:instalar` (o `--verificar` instala num banco limpo:
  `ferramentas/gerar-instalar.sh --verificar`).
