# Meu Dia de Gerente — Contrato técnico

Fonte única da verdade entre **banco (Supabase)**, **front (web/)** e **N8N (n8n/)**.
Seis agentes implementam em paralelo a partir deste documento (divisão em `docs/DIVISAO.md`).
Mudou algo? Atualize **aqui primeiro** e avise os donos afetados.

Palavras normativas: **DEVE** = obrigatório; **PODE** = opcional; o que não estiver escrito fica a critério
do dono do arquivo, desde que não quebre o contrato.

---

## 0. Visão geral e decisões principais

Sistema multiempresa para gerente de bar/restaurante/loja. Cada **empresa** é um estabelecimento ou rede.

| Tema | Decisão |
|---|---|
| Banco/Auth | Supabase: Postgres + RLS + Auth. **Sem Edge Functions**: tudo que precisa de privilégio é função SQL `security definer`. Instalar = rodar SQL (`supabase/instalar.sql`). |
| Integrações | **N8N** chama Zig e Control iD e grava no Supabase via PostgREST com a chave `service_role`, sempre por **RPCs de ingestão idempotentes** (`ingestao_*`). O front nunca fala com Zig/Control iD. |
| Segredos | Token Zig e URL/usuário/senha do Control iD ficam em `integracoes_segredos`, tabela **sem nenhum acesso** para `anon`/`authenticated`. O front só **escreve** (RPC) e consulta **quais chaves estão preenchidas**. |
| "Sincronizar agora" | **Fila no banco**: o front chama `sync_solicitar` (grava em `sync_solicitacoes`); o workflow N8N "Sincronizar agora" consulta a fila a cada 1 min (`ingestao_sync_pegar_solicitacoes`, com `for update skip locked`). Motivo: o front não conhece URL nem segredo do N8N (nada a vazar, sem CORS); funciona com o N8N atrás de firewall/na rede da loja (modelo *pull*, necessário para alcançar o Control iD na LAN); permissão e limite de frequência ficam na RLS/RPC; tudo auditável. Latência ≤ 1 min é aceitável. |
| Banco de horas | Os equipamentos **não** expõem banco de horas (só o software RHiD/iDSecure). O sistema **calcula** a partir das batidas + jornada/escala cadastrada, com saldo inicial e ajustes manuais (§7). |
| Dinheiro | Sempre **centavos** em `bigint`. Nunca `numeric` de reais, nunca `float`. |
| Tempo | Instantes em `timestamptz`. Fuso por empresa (`empresas.fuso`, padrão `America/Sao_Paulo`). **Dia de trabalho** começa em `empresas.virada_dia` (padrão `05:00`) — uma batida à 01:30 de domingo pertence ao dia de trabalho de sábado (§2.4). |
| Comissão | Serviço (gorjeta/10%) da Zig − retenção configurável (padrão 20%) = base distribuível; rateio por **pontos de comissão**; arredondamento pelo maior resto (§9). |
| Nomes | Português, sem acento, `snake_case` no banco; `camelCase` em TS; arquivos de página `PaginaX.tsx`. |

---

## 1. Stack e estrutura de pastas

- **Front**: Vite + React 18 + TypeScript (strict) + Tailwind CSS v4 (`@tailwindcss/vite`) + react-router-dom 7 +
  @tanstack/react-query 5 + @supabase/supabase-js 2 + zod + date-fns + lucide-react. Fontes via `@fontsource-variable/*`.
  Hospedagem: Vercel (`vercel.json`, SPA com rewrite para `/index.html`).
- **Testes**: vitest (lógica pura do front e bibliotecas JS do N8N), testes de banco em Postgres 16 local
  (`supabase/testes/`), Playwright (e2e em 390 px e 1440 px).
- **N8N**: workflows exportados em JSON (`n8n/**/workflows/*.json`) + bibliotecas JS puras testáveis (`n8n/**/lib/*.mjs`).

```
/
├─ docs/CONTRATO.md, docs/DIVISAO.md
├─ package.json, tsconfig.json, vite.config.ts, vercel.json, playwright.config.ts, .env.example, .gitignore
├─ web/
│  ├─ index.html
│  ├─ public/favicon.svg
│  └─ src/
│     ├─ main.tsx, App.tsx, estilos.css
│     ├─ tipos/banco.ts            ← tipos das tabelas/RPCs (espelho deste contrato)
│     ├─ lib/                      ← supabase.ts, sessao.tsx, formato.ts, csv.ts, permissoes.ts, rotulos.ts, consultas.ts, ...
│     ├─ componentes/              ← ui.tsx (design system), avisos.tsx, layout/, ...
│     └─ paginas/                  ← uma pasta por área (§14.4)
├─ supabase/
│  ├─ migrations/                  ← SQL idempotente, numerado por dono (§4)
│  ├─ seed/                        ← carga de demonstração (10_demo_base.sql, 20_demo_operacao.sql)
│  ├─ testes/                      ← 00_ambiente_supabase.sql, executar.sh, preparar-postgres.sh, NN_*.sql
│  ├─ instalar.sql                 ← GERADO por ferramentas/gerar-instalar.sh (não editar à mão)
│  └─ README.md
├─ ferramentas/
│  ├─ gerar-instalar.sh
│  └─ local/                       ← subir tudo na máquina (Postgres + PostgREST + portão de auth)
├─ n8n/
│  ├─ README.md, .env.example, verificar.mjs
│  ├─ comum/{workflows,lib}/       ← fila "sincronizar agora", agendador, rotina diária, exportação, erros
│  ├─ controlid/{workflows,lib}/   ← Control iD (acesso + REP/AFD)
│  ├─ zig/{workflows,lib}/         ← Zig
│  └─ mocks/                       ← servidores HTTP falsos da Zig e do Control iD + dados
└─ e2e/                            ← Playwright
```

Scripts do `package.json` (já existem no esqueleto; os donos implementam o que eles chamam):

| script | faz |
|---|---|
| `npm run dev` | Vite em `http://127.0.0.1:5173` |
| `npm run build` | `tsc -b --noEmit && vite build` → `dist/` |
| `npm run typecheck` | `tsc -b --noEmit` |
| `npm test` | vitest (`web/src/**/*.test.ts(x)` e `n8n/**/*.test.mjs`) |
| `npm run test:banco` | sobe Postgres 16 descartável e roda `supabase/testes/executar.sh` |
| `npm run sql:instalar` | regera `supabase/instalar.sql` |
| `npm run local` | `ferramentas/local/subir.sh` |
| `npm run test:e2e` | Playwright |
| `npm run n8n:verificar` | `node n8n/verificar.mjs` |
| `npm run n8n:mocks` | `node n8n/mocks/servidor.mjs` |

Variáveis do front (`.env.example`): `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_LOGIN_GOOGLE` (`true`/`false`, padrão `true`).

---

## 2. Convenções

### 2.1 Banco
- Todas as tabelas em `public`, RLS **ligada** em todas.
- `id uuid primary key default gen_random_uuid()` salvo indicação; `criado_em timestamptz not null default now()`;
  `atualizado_em timestamptz not null default now()` mantido por gatilho `tocar_atualizado_em()` (backend-1 cria a função; todos usam).
- Toda tabela de dados de empresa tem `empresa_id uuid not null references empresas(id) on delete cascade` e índice que começa por `empresa_id`.
  Em tabelas-filhas, `empresa_id` é **preenchido por gatilho a partir do pai** (o cliente pode omitir; valor divergente é sobrescrito).
- Toda FK tem índice.
- Migrações **idempotentes** (`create table if not exists`, `create or replace function`, `drop policy if exists` + `create policy`,
  `drop trigger if exists` + `create trigger`, `alter table ... add column if not exists`). `executar.sh` aplica tudo **duas vezes**.
- Toda função `security definer` tem `set search_path = public, extensions, pg_temp`.
- Lógica de negócio usa **`agora()`** (backend-1), nunca `now()` direto: `agora()` devolve `current_setting('app.agora', true)::timestamptz`
  quando definido e `now()` caso contrário. Os testes fixam o relógio com `set local app.agora = '2026-10-06 12:00:00-03'`.
- Erros de regra: `raise exception '<mensagem em português>' using errcode = '<código>'`, com `42501` (permissão), `22023` (valor inválido),
  `P0002` (não encontrado), `23505` (duplicado). As mensagens exatas estão em §10.9 — o front as mostra como vierem.

### 2.2 Etiquetas de privilégio (obrigatório)
A última migração (`…0900_permissoes.sql`, backend-1) **varre o catálogo** e concede privilégios lendo a primeira palavra
do `comment on` de cada objeto. Assim cada dono declara o acesso no próprio arquivo, sem editar o arquivo do outro.

| etiqueta (início do comentário) | tabela: `authenticated` recebe | função: quem executa |
|---|---|---|
| `[api:crud]` | `select, insert, update, delete` (a RLS decide as linhas) | — |
| `[api:leitura]` | só `select` (escrita só por RPC/gatilho) | — |
| `[api:nenhum]` | nada (só `service_role`) | — |
| `[api]` | — | `authenticated` + `service_role` |
| `[politica]` | — | `authenticated` + `service_role` (auxiliares usadas nas políticas RLS) |
| `[servico]` | — | só `service_role` (N8N) |
| `[interno]` ou sem etiqueta | — | ninguém além do dono (`postgres`) e `service_role` |

Regras da varredura: `anon` não recebe **nada** em tabela, sequência ou função de `public`; `revoke all ... from public, anon, authenticated`
antes de conceder; `service_role` recebe `all` em tabelas/sequências e `execute` em todas as funções. Tabela sem etiqueta = `[api:nenhum]`.
O teste `supabase/testes/90_auditoria.sql` falha se houver tabela de `public` sem etiqueta, função `security definer` sem `search_path`,
FK sem índice ou tabela sem RLS.

Exemplo: `comment on table public.funcionarios is '[api:crud] Funcionários da empresa.';`
`comment on function public.ponto_espelho(uuid, date, date) is '[api] Espelho de ponto.';`

### 2.3 Dinheiro
`bigint` em centavos, sufixo `_centavos` em colunas de cálculo nosso; colunas espelho da Zig mantêm o nome da API em snake_case
(`unit_value`, `valor`), também em centavos. Arredondamento de dinheiro: `round()` do Postgres em `numeric` (meio para longe do zero).

### 2.4 Tempo, fuso e dia de trabalho
- `empresas.fuso text` (IANA, validado contra `pg_timezone_names`), `empresas.virada_dia time` (padrão `05:00`).
- **Dia de trabalho** de um instante: `dia_de_trabalho(i, e) = ((i at time zone fuso) - virada_dia)::date`.
  Ex.: virada 05:00 — batida em 2026-10-04 01:30 (local) → dia de trabalho 2026-10-03; batida 05:00 → 2026-10-04.
- **Horário de escala** `t` (tipo `time`) no dia de trabalho `D` vira o instante
  `(D + t + (case when t < virada_dia then 1 else 0 end) * interval '1 day') at time zone fuso`.
  Ex.: jornada 17:00→01:00 em D=sábado: entrada sábado 17:00; saída domingo 01:00.
  Consequência documentada: jornadas cujo início seja **antes** da virada (ex.: padaria às 04:00) exigem ajustar `virada_dia` da empresa.
- **Dia encerrado**: `D < dia_de_trabalho_atual(e)`. Só dias encerrados geram alarmes de falta/ímpar e entram no banco de horas.
- Dia da semana: `extract(dow from D)` → 0 = domingo … 6 = sábado.
- Datas trafegam como `'YYYY-MM-DD'`; horas como `'HH:MM'` ou `'HH:MM:SS'`; instantes em ISO 8601 com fuso.

### 2.5 Escopo de empresa nas RPCs
Toda RPC de leitura/ação que não recebe um id de registro aceita `p_empresa uuid default null`, resolvido por
`resolver_empresa(p_empresa, nivel)` (backend-1, `[interno]`):
1. `v := coalesce(p_empresa, minha_empresa())`; se `null` → erro `Informe a empresa` (22023) (acontece com o master sem `p_empresa`).
2. `nivel = 'ler'` exige `pode_ler(v)`; `'operar'` exige `pode_operar(v)`; `'administrar'` exige `pode_administrar(v)`; senão `Sem permissão` (42501).
RPCs que recebem id de registro (funcionário, alarme, fechamento…) derivam a empresa do registro e aplicam o mesmo teste.

---

## 3. Papéis e permissões

| papel | `empresa_id` | resumo |
|---|---|---|
| `master` | `null` | Dono da plataforma. Vê e edita tudo de todas as empresas; cria/desativa/exclui empresas. Não é criado pela API. |
| `administrador` | obrigatória* | Tudo da própria empresa: usuários, integrações (inclusive segredos), configurações, **fechar** comissão, excluir. |
| `gerente` | obrigatória | Operação do dia: funcionários, jornadas, ponto (ajustes, justificativas, abonos), banco de horas (ajustes), tarefas, sincronizar agora, comissões em **rascunho**. Não gerencia usuários/integrações nem fecha comissão. |
| `leitura` | obrigatória | Somente leitura de painel, funcionários, ponto, banco de horas, vendas, tarefas. Não vê comissões, integrações, usuários. Pode mudar status/itens das **tarefas atribuídas a ele** (via `perfis.funcionario_id` ou `responsavel_perfil_id`). |

\* Perfil sem empresa (cadastro aberto, antes de `criar_minha_empresa`) não enxerga nada; o front o manda para `/comecar`.
Empresa com `ativa = false` ou perfil com `ativo = false`: não enxerga nada (o próprio perfil continua legível para a tela explicar).

### 3.1 Funções auxiliares das políticas (backend-1, `[politica]`, `stable security definer`)
| função | retorno |
|---|---|
| `eh_master()` | `bool` — perfil ativo com papel master |
| `meu_papel()` | `text` |
| `minha_empresa()` | `uuid` — empresa do perfil (null para master) |
| `meu_funcionario()` | `uuid` — `perfis.funcionario_id` |
| `empresa_leitura()` | `uuid` — empresa se perfil ativo, empresa ativa, papel ∈ {administrador, gerente, leitura}; senão null |
| `empresa_operacao()` | idem, papel ∈ {administrador, gerente} |
| `empresa_administracao()` | idem, papel = administrador |
| `pode_ler(e uuid)` / `pode_operar(e uuid)` / `pode_administrar(e uuid)` | `bool` — master ou a empresa correspondente acima = `e` |

Forma canônica das políticas (calcula a função uma vez por consulta):
- ler: `using ((select eh_master()) or empresa_id = (select empresa_leitura()))`
- operar: `... or empresa_id = (select empresa_operacao())` (em `with check` também)
- administrar: `... or empresa_id = (select empresa_administracao())`

### 3.2 Matriz por tabela
L = leitura, G = gerente, A = administrador, M = master (M sempre pode tudo o que A pode, em qualquer empresa).

| tabela | etiqueta | select | insert | update | delete | dono |
|---|---|---|---|---|---|---|
| empresas | `[api:crud]` | L G A (a própria) | M | A (exceto `ativa`), M | M | b1 |
| perfis | `[api:leitura]` | o próprio sempre; L G A da mesma empresa | RPC | RPC | RPC | b1 |
| configuracao | `[api:leitura]` | M | — | — | — | b1 |
| funcionarios | `[api:crud]` | L G A | G A | G A | A | b1 |
| funcionario_pontos | `[api:leitura]` | G A | gatilho | gatilho | — | b1 |
| jornadas, jornada_dias, funcionario_jornadas | `[api:crud]` | L G A | G A | G A | G A | b1 |
| controlid_usuarios | `[api:leitura]` | G A | ingestão | RPC `funcionario_vincular_controlid` | — | b1 |
| integracoes | `[api:crud]` | G A | A | A (gatilho preserva `cursor`, `ultimo_*`) | A | b1 |
| integracoes_segredos | `[api:nenhum]` | — | RPC (A) | RPC (A) | cascata | b1 |
| sync_solicitacoes | `[api:leitura]` | G A | RPC | — | — | b1 |
| sync_execucoes | `[api:leitura]` | L G A | serviço | serviço | — | b1 |
| tarefas_rotinas, tarefas_rotina_itens | `[api:crud]` | L G A | G A | G A | G A | b1 |
| tarefas, tarefa_itens | `[api:crud]` | L G A | G A | G A (L via RPC) | G A | b1 |
| ponto_batidas | `[api:leitura]` | L G A | RPC/ingestão | RPC | — | b2 |
| ponto_dias | `[api:leitura]` | L G A | apuração | apuração | — | b2 |
| ponto_alarmes | `[api:leitura]` | L G A | apuração | RPC/apuração | — | b2 |
| ponto_ajustes | `[api:leitura]` | G A | RPC | — | — | b2 |
| ponto_abonos | `[api:leitura]` | L G A | RPC (G A) | — | RPC (G A) | b2 |
| banco_horas_lancamentos | `[api:leitura]` | L G A | RPC (G A; saldo inicial só A) | — | RPC (A) | b2 |
| zig_lojas | `[api:crud]` | L G A | ingestão | A (só `sincronizar`, gatilho) | — | b2 |
| zig_vendas_itens, zig_faturamento, zig_faturamento_bandeiras | `[api:leitura]` | L G A | ingestão | — | — | b2 |
| zig_compradores | `[api:leitura]` | G A | ingestão | — | — | b2 |
| comissao_fechamentos, comissao_itens | `[api:leitura]` | G A | RPC | RPC | RPC | b2 |

Nas tabelas `[api:crud]`, quem não tem política para a operação recebe 0 linhas (update/delete) ou erro de RLS (insert).

---
## 4. Migrações (ordem e dono)

| arquivo | dono | conteúdo |
|---|---|---|
| `20261006000100_base.sql` | backend-1 | extensões, `agora()`, `tocar_atualizado_em()`, empresas, perfis, configuracao, auxiliares (§3.1), `dia_de_trabalho*`, `resolver_empresa`, gatilho em `auth.users`, RPCs de usuários/empresa, RLS dessas tabelas |
| `20261006000110_cadastros.sql` | backend-1 | funcionarios, funcionario_pontos, jornadas, jornada_dias, funcionario_jornadas, `perfis.funcionario_id`, `pontos_vigentes()`, RLS |
| `20261006000120_integracoes_sync.sql` | backend-1 | integracoes, integracoes_segredos, controlid_usuarios, sync_solicitacoes, sync_execucoes, RPCs de integração/sync/usuários Control iD, RLS |
| `20261006000130_tarefas.sql` | backend-1 | tarefas_rotinas, tarefas_rotina_itens, tarefas, tarefa_itens, RPCs de tarefas, RLS |
| `20261006000200_ponto.sql` | backend-2 | ponto_batidas, ponto_dias, ponto_alarmes, ponto_ajustes, ponto_abonos, banco_horas_lancamentos, apuração, RPCs de ponto/banco de horas, gatilhos em tabelas do backend-1 (§7.8), RLS |
| `20261006000210_zig.sql` | backend-2 | zig_lojas, zig_vendas_itens, zig_faturamento, zig_faturamento_bandeiras, zig_compradores, RPCs de vendas, RLS |
| `20261006000220_comissoes.sql` | backend-2 | comissao_fechamentos, comissao_itens, RPCs de comissão, RLS |
| `20261006000230_ingestao.sql` | backend-2 | `ingestao_controlid_batidas`, `ingestao_zig_*`, `ingestao_apurar_ponto`, `ingestao_fechamento_exportar` |
| `20261006000240_painel.sql` | backend-2 | `painel_do_dia` |
| `20261006000900_permissoes.sql` | backend-1 | varredura de privilégios por etiqueta (§2.2). **Sempre a última.** |

O backend-2 escreve contra o DDL do §5 **exatamente** como está aqui (nomes, tipos, nulidade).
Se o backend-1 precisar mudar algo do §5, muda este documento antes.

---

## 5. DDL — backend-1 (tabelas base)

```sql
-- ===================================================================== empresas
create table if not exists public.empresas (
  id                              uuid primary key default gen_random_uuid(),
  nome                            text not null check (btrim(nome) <> ''),
  cnpj                            text check (cnpj is null or cnpj ~ '^[0-9]{14}$'),
  telefone                        text,
  cidade                          text,
  uf                              text check (uf is null or uf ~ '^[A-Z]{2}$'),
  fuso                            text not null default 'America/Sao_Paulo',   -- validado por gatilho (pg_timezone_names)
  virada_dia                      time not null default '05:00',
  comissao_percentual_retencao    numeric(5,2) not null default 20
                                  check (comissao_percentual_retencao between 0 and 100),
  ponto_alarme_atraso             boolean not null default false,
  ponto_janela_duplicada_minutos  int not null default 2 check (ponto_janela_duplicada_minutos between 0 and 30),
  ativa                           boolean not null default true,
  criado_em                       timestamptz not null default now(),
  atualizado_em                   timestamptz not null default now()
);
-- '[api:crud]'. Administrador não altera `ativa` (gatilho: mantém o valor antigo e segue; master altera).

-- ======================================================================= perfis
create table if not exists public.perfis (
  id          uuid primary key references auth.users (id) on delete cascade,
  nome        text not null,
  email       text not null,
  papel       text not null default 'administrador'
              check (papel in ('master', 'administrador', 'gerente', 'leitura')),
  empresa_id  uuid references public.empresas (id) on delete cascade,
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now(),
  constraint perfis_master_sem_empresa check (papel <> 'master' or empresa_id is null)
);
create index if not exists perfis_empresa_idx on public.perfis (empresa_id);
-- Em 0110: alter table public.perfis add column if not exists
--   funcionario_id uuid references public.funcionarios (id) on delete set null;  (+ índice)
-- '[api:leitura]'

-- ================================================================= configuracao
create table if not exists public.configuracao (
  id               int primary key default 1 check (id = 1),
  master_email     text,                       -- quem se cadastrar com este e-mail vira master (se ainda não houver master)
  cadastro_aberto  boolean not null default true  -- false: criar_minha_empresa recusa
);
insert into public.configuracao (id) values (1) on conflict (id) do nothing;
-- '[api:leitura]' (RLS: só master)

-- ================================================================= funcionarios
create table if not exists public.funcionarios (
  id                   uuid primary key default gen_random_uuid(),
  empresa_id           uuid not null references public.empresas (id) on delete cascade,
  nome                 text not null check (btrim(nome) <> ''),
  apelido              text,
  matricula            text,          -- vazio no insert → gatilho gera sequencial por empresa ('1','2',...) = registration no Control iD
  cpf                  text check (cpf is null or cpf ~ '^[0-9]{11}$'),
  pis                  text check (pis is null or pis ~ '^[0-9]{11}$'),
  cargo                text,          -- ex.: Garçom, Cumim, Bartender, Cozinha
  telefone             text,
  email                text,
  zig_employee_name    text,          -- exatamente como vem em employeeName da Zig (comparação: lower(btrim()))
  pontos_comissao      numeric(8,2) not null default 0 check (pontos_comissao >= 0),
  participa_comissao   boolean not null default true,
  data_admissao        date,
  data_desligamento    date,
  ativo                boolean not null default true,
  observacoes          text,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now(),
  constraint funcionarios_datas check (data_desligamento is null or data_admissao is null
                                       or data_desligamento >= data_admissao)
);
create index if not exists funcionarios_empresa_idx on public.funcionarios (empresa_id);
create unique index if not exists funcionarios_matricula_uk on public.funcionarios (empresa_id, matricula)
  where matricula is not null;
create unique index if not exists funcionarios_cpf_uk on public.funcionarios (empresa_id, cpf) where cpf is not null;
create unique index if not exists funcionarios_pis_uk on public.funcionarios (empresa_id, pis) where pis is not null;
create unique index if not exists funcionarios_zig_uk on public.funcionarios (empresa_id, lower(btrim(zig_employee_name)))
  where zig_employee_name is not null;
-- '[api:crud]'. Gatilhos: cpf/pis normalizados para só dígitos ('' → null); zig_employee_name btrim ('' → null);
-- empresa_id imutável; ao inserir ou mudar pontos_comissao grava funcionario_pontos (abaixo).

-- =========================================================== funcionario_pontos
-- Histórico de pontos de comissão. Escrito SÓ pelo gatilho de funcionarios.
create table if not exists public.funcionario_pontos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid not null references public.funcionarios (id) on delete cascade,
  pontos          numeric(8,2) not null check (pontos >= 0),
  vigente_desde   date not null,
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now(),
  unique (funcionario_id, vigente_desde)
);
create index if not exists funcionario_pontos_empresa_idx on public.funcionario_pontos (empresa_id);
-- Regra do gatilho: no INSERT de funcionário → vigente_desde = coalesce(data_admissao, dia_de_trabalho_atual(empresa));
-- no UPDATE com pontos_comissao diferente → vigente_desde = dia_de_trabalho_atual(empresa) (mesmo dia: upsert).
-- '[api:leitura]'
-- pontos_vigentes(p_funcionario uuid, p_data date) returns numeric  [api]
--   = pontos da linha com maior vigente_desde <= p_data; se não houver, a de MENOR vigente_desde;
--     se não houver histórico, funcionarios.pontos_comissao.

-- ===================================================================== jornadas
create table if not exists public.jornadas (
  id                         uuid primary key default gen_random_uuid(),
  empresa_id                 uuid not null references public.empresas (id) on delete cascade,
  nome                       text not null check (btrim(nome) <> ''),
  tolerancia_batida_minutos  int not null default 5 check (tolerancia_batida_minutos between 0 and 60),   -- atraso
  tolerancia_diaria_minutos  int not null default 10 check (tolerancia_diaria_minutos between 0 and 120), -- saldo ≈ 0
  ativa                      boolean not null default true,
  criado_em                  timestamptz not null default now(),
  atualizado_em              timestamptz not null default now(),
  unique (empresa_id, nome)
);
-- '[api:crud]'

create table if not exists public.jornada_dias (
  id                  uuid primary key default gen_random_uuid(),
  empresa_id          uuid not null references public.empresas (id) on delete cascade,   -- gatilho: da jornada
  jornada_id          uuid not null references public.jornadas (id) on delete cascade,
  dia_semana          smallint not null check (dia_semana between 0 and 6),             -- 0 = domingo
  entrada             time not null,
  saida_intervalo     time,
  volta_intervalo     time,
  saida               time not null,
  batidas_esperadas   smallint generated always as (case when saida_intervalo is null then 2 else 4 end) stored,
  minutos_previstos   int generated always as (
      (((extract(epoch from (saida - entrada)) / 60)::int + 1440) % 1440)
    - coalesce((((extract(epoch from (volta_intervalo - saida_intervalo)) / 60)::int + 1440) % 1440), 0)
  ) stored,
  unique (jornada_id, dia_semana),
  constraint jornada_dias_intervalo check ((saida_intervalo is null) = (volta_intervalo is null))
);
create index if not exists jornada_dias_empresa_idx on public.jornada_dias (empresa_id);
-- Dia da semana sem linha = folga. Gatilho valida a ordem circular a partir da entrada
-- (entrada < saida_intervalo < volta_intervalo < saida, "módulo 24h", total < 24h) → erro 'Horários da jornada fora de ordem'.
-- Ex.: 17:00 / 21:00 / 21:30 / 01:00 → minutos_previstos = 480 - 30 = 450. '[api:crud]'

create table if not exists public.funcionario_jornadas (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,   -- gatilho: do funcionário
  funcionario_id  uuid not null references public.funcionarios (id) on delete cascade,
  jornada_id      uuid not null references public.jornadas (id) on delete restrict,
  vigente_desde   date not null,
  criado_em       timestamptz not null default now(),
  unique (funcionario_id, vigente_desde)
);
create index if not exists funcionario_jornadas_empresa_idx on public.funcionario_jornadas (empresa_id);
create index if not exists funcionario_jornadas_jornada_idx on public.funcionario_jornadas (jornada_id);
-- Jornada vigente em D = linha com maior vigente_desde <= D. Jornada e funcionário da mesma empresa (gatilho:
-- 'Jornada de outra empresa'). '[api:crud]'

-- ================================================================== integracoes
create table if not exists public.integracoes (
  id                   uuid primary key default gen_random_uuid(),
  empresa_id           uuid not null references public.empresas (id) on delete cascade,
  tipo                 text not null check (tipo in ('zig', 'controlid_acesso', 'controlid_rep')),
  nome                 text not null check (btrim(nome) <> ''),    -- ex.: 'Zig', 'iDFace porta dos fundos', 'iDClass salão'
  ativa                boolean not null default true,
  parametros           jsonb not null default '{}'::jsonb,          -- NÃO secreto; formato em §11.1
  intervalo_minutos    int not null default 60 check (intervalo_minutos >= 15),
  cursor               jsonb not null default '{}'::jsonb,          -- mantido pela ingestão; o front não altera
  ultimo_sucesso_em    timestamptz,
  ultima_execucao_em   timestamptz,
  ultimo_status        text check (ultimo_status in ('sucesso', 'parcial', 'erro')),
  ultimo_erro          text,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now()
);
create index if not exists integracoes_empresa_idx on public.integracoes (empresa_id);
create unique index if not exists integracoes_zig_uk on public.integracoes (empresa_id) where tipo = 'zig';
-- '[api:crud]'. Gatilho: se quem altera é `authenticated`, mantém cursor/ultimo_* antigos; tipo e empresa_id imutáveis.

create table if not exists public.integracoes_segredos (
  integracao_id  uuid primary key references public.integracoes (id) on delete cascade,
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  segredos       jsonb not null default '{}'::jsonb,                -- formato em §11.1
  atualizado_em  timestamptz not null default now()
);
create index if not exists integracoes_segredos_empresa_idx on public.integracoes_segredos (empresa_id);
-- '[api:nenhum]'. RLS ligada e SEM políticas para authenticated.

-- ============================================================ controlid_usuarios
-- Espelho dos usuários cadastrados em cada equipamento Control iD (snapshot completo a cada importação).
create table if not exists public.controlid_usuarios (
  id                       uuid primary key default gen_random_uuid(),
  empresa_id               uuid not null references public.empresas (id) on delete cascade,
  integracao_id            uuid not null references public.integracoes (id) on delete cascade,
  user_id_externo          text not null,     -- acesso: users.id ; REP: CPF ou PIS (só dígitos)
  registration             text,
  nome                     text,
  cpf                      text,
  pis                      text,
  funcionario_id           uuid references public.funcionarios (id) on delete set null,
  vinculo                  text check (vinculo in ('automatico', 'manual')),
  removido_no_equipamento  boolean not null default false,
  visto_em                 timestamptz not null default now(),
  criado_em                timestamptz not null default now(),
  unique (integracao_id, user_id_externo)
);
create index if not exists controlid_usuarios_empresa_idx on public.controlid_usuarios (empresa_id);
create index if not exists controlid_usuarios_funcionario_idx on public.controlid_usuarios (funcionario_id);
create unique index if not exists controlid_usuarios_func_uk on public.controlid_usuarios (integracao_id, funcionario_id)
  where funcionario_id is not null;
-- '[api:leitura]'

-- ============================================================ sync_solicitacoes
create table if not exists public.sync_solicitacoes (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  integracao_id   uuid references public.integracoes (id) on delete cascade,   -- null p/ 'apurar_ponto','exportar_fechamento'
  escopo          text not null check (escopo in ('tudo', 'funcionarios', 'batidas', 'vendas',
                                                  'exportar_funcionarios', 'apurar_ponto', 'exportar_fechamento')),
  data_inicio     date,
  data_fim        date,
  parametros      jsonb not null default '{}'::jsonb,   -- exportar_fechamento: {"fechamento_id": uuid}
  status          text not null default 'pendente'
                  check (status in ('pendente', 'em_andamento', 'concluida', 'erro', 'cancelada')),
  solicitado_por  uuid references public.perfis (id) on delete set null,
  solicitado_em   timestamptz not null default now(),
  pego_em         timestamptz,
  concluido_em    timestamptz,
  execucao_id     uuid,          -- sem FK (a execução pode ser apagada por limpeza)
  mensagem        text,
  constraint sync_solicitacoes_periodo check (data_fim is null or data_inicio is null or data_fim >= data_inicio)
);
create index if not exists sync_solicitacoes_empresa_idx on public.sync_solicitacoes (empresa_id, solicitado_em desc);
create index if not exists sync_solicitacoes_integracao_idx on public.sync_solicitacoes (integracao_id);
create index if not exists sync_solicitacoes_fila_idx on public.sync_solicitacoes (solicitado_em) where status = 'pendente';
-- '[api:leitura]'

-- =============================================================== sync_execucoes
create table if not exists public.sync_execucoes (
  id                   uuid primary key default gen_random_uuid(),
  empresa_id           uuid references public.empresas (id) on delete cascade,     -- null = rotina global
  integracao_id        uuid references public.integracoes (id) on delete set null,
  solicitacao_id       uuid references public.sync_solicitacoes (id) on delete set null,
  tipo                 text not null check (tipo in ('zig_lojas', 'zig_faturamento', 'zig_vendas', 'zig_compradores',
                         'zig_importar', 'controlid_usuarios', 'controlid_batidas', 'controlid_exportar_usuarios',
                         'apurar_ponto', 'tarefas_gerar', 'exportar_fechamento')),
  gatilho              text not null check (gatilho in ('agendado', 'manual', 'webhook')),
  workflow             text not null,          -- nome do workflow N8N
  n8n_execution_id     text,
  status               text not null default 'executando' check (status in ('executando', 'sucesso', 'parcial', 'erro')),
  iniciado_em          timestamptz not null default now(),
  finalizado_em        timestamptz,
  periodo_inicio       date,
  periodo_fim          date,
  registros_lidos      int not null default 0,
  registros_gravados   int not null default 0,
  registros_ignorados  int not null default 0,
  tentativas           int not null default 1,
  erro                 text,
  detalhes             jsonb not null default '{}'::jsonb
);
create index if not exists sync_execucoes_empresa_idx on public.sync_execucoes (empresa_id, iniciado_em desc);
create index if not exists sync_execucoes_integracao_idx on public.sync_execucoes (integracao_id, iniciado_em desc);
create index if not exists sync_execucoes_solicitacao_idx on public.sync_execucoes (solicitacao_id);
-- '[api:leitura]'. RLS: L G A da empresa (empresa_id null: só master).

-- ======================================================================= tarefas
create table if not exists public.tarefas_rotinas (
  id                          uuid primary key default gen_random_uuid(),
  empresa_id                  uuid not null references public.empresas (id) on delete cascade,
  titulo                      text not null check (btrim(titulo) <> ''),
  descricao                   text,
  recorrencia                 text not null default 'diaria' check (recorrencia in ('diaria', 'semanal', 'mensal')),
  dias_semana                 smallint[] not null default '{}',   -- semanal: obrigatório, valores 0..6
  dia_mes                     smallint check (dia_mes between 1 and 31),  -- mensal: obrigatório; mês curto → último dia
  horario_limite              time,
  prioridade                  text not null default 'normal' check (prioridade in ('baixa', 'normal', 'alta')),
  responsavel_funcionario_id  uuid references public.funcionarios (id) on delete set null,
  responsavel_perfil_id       uuid references public.perfis (id) on delete set null,
  ativa                       boolean not null default true,
  criado_por                  uuid references public.perfis (id) on delete set null default auth.uid(),
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),
  constraint tarefas_rotinas_semanal check (recorrencia <> 'semanal' or cardinality(dias_semana) > 0),
  constraint tarefas_rotinas_mensal check (recorrencia <> 'mensal' or dia_mes is not null)
);
create table if not exists public.tarefas_rotina_itens (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas (id) on delete cascade,   -- gatilho: da rotina
  rotina_id   uuid not null references public.tarefas_rotinas (id) on delete cascade,
  ordem       int not null default 0,
  texto       text not null check (btrim(texto) <> '')
);
create table if not exists public.tarefas (
  id                          uuid primary key default gen_random_uuid(),
  empresa_id                  uuid not null references public.empresas (id) on delete cascade,
  rotina_id                   uuid references public.tarefas_rotinas (id) on delete set null,
  data                        date not null,                    -- dia de trabalho
  titulo                      text not null check (btrim(titulo) <> ''),
  descricao                   text,
  horario_limite              time,
  prioridade                  text not null default 'normal' check (prioridade in ('baixa', 'normal', 'alta')),
  status                      text not null default 'pendente'
                              check (status in ('pendente', 'em_andamento', 'concluida', 'cancelada')),
  responsavel_funcionario_id  uuid references public.funcionarios (id) on delete set null,
  responsavel_perfil_id       uuid references public.perfis (id) on delete set null,
  concluida_por               uuid references public.perfis (id) on delete set null,
  concluida_em                timestamptz,
  criado_por                  uuid references public.perfis (id) on delete set null default auth.uid(),
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),
  unique (rotina_id, data)
);
create table if not exists public.tarefa_itens (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas (id) on delete cascade,   -- gatilho: da tarefa
  tarefa_id   uuid not null references public.tarefas (id) on delete cascade,
  ordem       int not null default 0,
  texto       text not null check (btrim(texto) <> ''),
  feito       boolean not null default false,
  feito_por   uuid references public.perfis (id) on delete set null,
  feito_em    timestamptz
);
-- índices: (empresa_id), (empresa_id, data) em tarefas, e um por FK. Todas '[api:crud]'.
-- Gatilho em tarefas: status → 'concluida' preenche concluida_por = auth.uid(), concluida_em = agora(); sair de
-- 'concluida' limpa os dois. Gatilho em tarefa_itens: feito → feito_por/feito_em idem.
-- "Atrasada" (calculado, não coluna): status in (pendente, em_andamento) e (data < hoje_trabalho
--   ou (data = hoje_trabalho e horario_limite < hora local atual)).
```

---

## 6. DDL — backend-2 (ponto, Zig, comissões)

```sql
-- ================================================================= ponto_batidas
create table if not exists public.ponto_batidas (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid references public.funcionarios (id) on delete cascade,   -- null = ainda sem vínculo
  integracao_id   uuid references public.integracoes (id) on delete set null,
  origem          text not null check (origem in ('controlid_acesso', 'controlid_rep', 'manual')),
  id_externo      text,          -- acesso: access_logs.id ; REP: NSR (texto, sem zeros à esquerda)
  pessoa_externa  text,          -- acesso: user_id ; REP: CPF/PIS só dígitos
  instante        timestamptz not null,
  data_trabalho   date not null, -- gatilho: dia_de_trabalho(instante, empresa_id); recalculado se instante mudar
  desconsiderada  boolean not null default false,
  motivo          text,          -- obrigatório em origem 'manual' e ao desconsiderar
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now(),
  constraint ponto_batidas_externa_uk unique (integracao_id, id_externo),
  constraint ponto_batidas_origem check (
    (origem = 'manual' and funcionario_id is not null and motivo is not null and id_externo is null)
    or (origem <> 'manual' and id_externo is not null and integracao_id is not null))
);
-- (o check acima vale na INSERÇÃO; se a integração for excluída, integracao_id vira null — implemente o check
--  como gatilho BEFORE INSERT para não quebrar o "on delete set null")
create index if not exists ponto_batidas_func_dia_idx on public.ponto_batidas (funcionario_id, data_trabalho);
create index if not exists ponto_batidas_empresa_dia_idx on public.ponto_batidas (empresa_id, data_trabalho);
create index if not exists ponto_batidas_sem_func_idx on public.ponto_batidas (empresa_id, integracao_id, pessoa_externa)
  where funcionario_id is null;
-- '[api:leitura]'. Batidas importadas são imutáveis (só `desconsiderada`/`motivo` mudam, via RPC).

-- =================================================================== ponto_dias
-- Resultado persistido da apuração (uma linha por funcionário × dia de trabalho apurado).
create table if not exists public.ponto_dias (
  funcionario_id      uuid not null references public.funcionarios (id) on delete cascade,
  data                date not null,
  empresa_id          uuid not null references public.empresas (id) on delete cascade,
  jornada_id          uuid references public.jornadas (id) on delete set null,
  abono_tipo          text,          -- tipo do abono do dia, se houver
  batidas_esperadas   smallint not null default 0,
  batidas_validas     smallint not null default 0,   -- não desconsideradas e não duplicadas
  batidas_duplicadas  smallint not null default 0,
  previsto_minutos    int not null default 0,
  trabalhado_minutos  int not null default 0,
  saldo_minutos       int not null default 0,
  atraso_minutos      int not null default 0,
  primeira_batida     timestamptz,
  ultima_batida       timestamptz,
  situacao            text not null check (situacao in ('completo', 'incompleto', 'ausente', 'folga',
                                                        'sem_escala', 'abonado', 'em_andamento')),
  encerrado           boolean not null,
  alarmes_abertos     smallint not null default 0,
  apurado_em          timestamptz not null default now(),
  primary key (funcionario_id, data)
);
create index if not exists ponto_dias_empresa_idx on public.ponto_dias (empresa_id, data);
create index if not exists ponto_dias_jornada_idx on public.ponto_dias (jornada_id);
-- '[api:leitura]'

-- ================================================================ ponto_alarmes
create table if not exists public.ponto_alarmes (
  id                         uuid primary key default gen_random_uuid(),
  empresa_id                 uuid not null references public.empresas (id) on delete cascade,
  funcionario_id             uuid not null references public.funcionarios (id) on delete cascade,
  data                       date not null,
  tipo                       text not null check (tipo in ('batida_faltando', 'batidas_impares',
                                                           'sem_batida_dia_escalado', 'atraso')),
  batida_esperada            text not null default ''
                             check (batida_esperada in ('', 'entrada', 'saida_intervalo', 'volta_intervalo', 'saida')),
  horario_previsto           timestamptz,   -- batida_faltando/atraso: instante previsto da batida
  minutos                    int,           -- atraso: minutos de atraso
  detalhe                    text not null, -- texto pronto para exibir (ex.: 'Faltou a volta do intervalo (21:30)')
  status                     text not null default 'aberto' check (status in ('aberto', 'justificado', 'resolvido')),
  justificativa              text,
  justificado_por            uuid references public.perfis (id) on delete set null,
  justificado_em             timestamptz,
  resolvido_em               timestamptz,
  resolvido_automaticamente  boolean not null default false,
  criado_em                  timestamptz not null default now(),
  atualizado_em              timestamptz not null default now(),
  unique (funcionario_id, data, tipo, batida_esperada)
);
create index if not exists ponto_alarmes_empresa_idx on public.ponto_alarmes (empresa_id, status, data desc);
-- '[api:leitura]'

-- ================================================================= ponto_ajustes
-- Auditoria de toda intervenção manual em batidas.
create table if not exists public.ponto_ajustes (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  funcionario_id   uuid not null references public.funcionarios (id) on delete cascade,
  batida_id        uuid references public.ponto_batidas (id) on delete set null,
  acao             text not null check (acao in ('incluir', 'desconsiderar', 'restaurar')),
  instante         timestamptz not null,       -- da batida afetada
  motivo           text not null,
  feito_por        uuid references public.perfis (id) on delete set null,
  feito_por_nome   text not null,              -- nome do perfil no momento ('Sistema' sem JWT)
  feito_em         timestamptz not null default now()
);
-- índices por empresa_id/funcionario_id/batida_id. '[api:leitura]'

-- ================================================================== ponto_abonos
create table if not exists public.ponto_abonos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid references public.funcionarios (id) on delete cascade,   -- null = empresa toda (feriado)
  data            date not null,
  tipo            text not null check (tipo in ('folga', 'feriado', 'ferias', 'atestado', 'compensacao', 'outro')),
  motivo          text,
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now(),
  constraint ponto_abonos_uk unique nulls not distinct (empresa_id, funcionario_id, data)
);
-- '[api:leitura]'. Abono do funcionário prevalece sobre o da empresa no mesmo dia.

-- ======================================================= banco_horas_lancamentos
create table if not exists public.banco_horas_lancamentos (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  funcionario_id   uuid not null references public.funcionarios (id) on delete cascade,
  data             date not null,
  tipo             text not null check (tipo in ('saldo_inicial', 'ajuste', 'compensacao', 'pagamento')),
  minutos          int not null,               -- com sinal (+ crédito, − débito)
  motivo           text not null check (btrim(motivo) <> ''),
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now()
);
create unique index if not exists banco_horas_saldo_inicial_uk on public.banco_horas_lancamentos (funcionario_id, data)
  where tipo = 'saldo_inicial';
-- '[api:leitura]'

-- ===================================================================== zig_lojas
create table if not exists public.zig_lojas (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  integracao_id    uuid not null references public.integracoes (id) on delete cascade,
  loja_id_externo  text not null,       -- id da Zig (texto)
  nome             text not null,
  sincronizar      boolean not null default true,
  visto_em         timestamptz not null default now(),
  criado_em        timestamptz not null default now(),
  unique (empresa_id, loja_id_externo)
);
-- '[api:crud]' com política de UPDATE só para administrador; gatilho só deixa `authenticated` mudar `sincronizar`.

-- ============================================================== zig_vendas_itens
-- Linhas de /erp/saida-produtos. data_operacao = dia consultado (dtinicio = dtfim = data_operacao).
create table if not exists public.zig_vendas_itens (
  id                 bigint generated always as identity primary key,
  empresa_id         uuid not null references public.empresas (id) on delete cascade,
  loja_id_externo    text not null,
  data_operacao      date not null,
  transaction_id     text not null,
  transaction_date   timestamptz,
  event_id           text,
  event_date         date,
  invoice_id         text,
  product_id         text,
  product_sku        text,
  product_name       text,
  product_category   text,
  tipo               text not null check (tipo in ('Normal', 'Couvert', 'ZigCard', 'Entrance', 'Tip', 'Outro')),
  tipo_original      text,                         -- valor cru de `type`
  unit_value         bigint not null default 0,    -- centavos
  quantidade         numeric(14,3) not null default 0,   -- `count`
  fractional_amount  numeric(14,3),
  fraction_unit      text,
  discount_value     bigint not null default 0,    -- centavos
  valor_total        bigint not null,              -- round(unit_value * quantidade) - discount_value
  employee_name      text,
  additions          jsonb not null default '[]'::jsonb,
  importado_em       timestamptz not null default now()
);
create index if not exists zig_vendas_itens_dia_idx on public.zig_vendas_itens (empresa_id, data_operacao, loja_id_externo);
create index if not exists zig_vendas_itens_garcom_idx on public.zig_vendas_itens (empresa_id, lower(btrim(employee_name)));
-- '[api:leitura]'

create table if not exists public.zig_faturamento (
  id               bigint generated always as identity primary key,
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  loja_id_externo  text not null,
  data_operacao    date not null,
  event_id         text,
  event_date       date,
  payment_id       int not null,
  payment_name     text not null,
  valor            bigint not null,    -- centavos
  importado_em     timestamptz not null default now()
);
create index if not exists zig_faturamento_dia_idx on public.zig_faturamento (empresa_id, data_operacao, loja_id_externo);

create table if not exists public.zig_faturamento_bandeiras (
  id               bigint generated always as identity primary key,
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  loja_id_externo  text not null,
  data_operacao    date not null,
  event_id         text,
  payment_id       int not null,
  payment_name     text,
  card_brand       text,
  valor            bigint not null,    -- totalValue (centavos)
  importado_em     timestamptz not null default now()
);
create index if not exists zig_bandeiras_dia_idx on public.zig_faturamento_bandeiras (empresa_id, data_operacao, loja_id_externo);

-- /erp/compradores SEM dados pessoais (LGPD: minimização — não guardamos documento, nome, telefone, e-mail).
create table if not exists public.zig_compradores (
  id               bigint generated always as identity primary key,
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  loja_id_externo  text not null,
  data_operacao    date not null,
  transaction_id   text not null,
  products_value   bigint not null default 0,
  tip_value        bigint not null default 0,
  importado_em     timestamptz not null default now()
);
create index if not exists zig_compradores_dia_idx on public.zig_compradores (empresa_id, data_operacao, loja_id_externo);
-- zig_faturamento, zig_faturamento_bandeiras, zig_compradores: '[api:leitura]'

-- ========================================================== comissao_fechamentos
create table if not exists public.comissao_fechamentos (
  id                          uuid primary key default gen_random_uuid(),
  empresa_id                  uuid not null references public.empresas (id) on delete cascade,
  titulo                      text not null,                 -- padrão: 'Comissão dd/mm a dd/mm/aaaa'
  data_inicio                 date not null,
  data_fim                    date not null,
  loja_id_externo             text,                          -- null = todas as lojas
  status                      text not null default 'rascunho' check (status in ('rascunho', 'fechado')),
  servico_zig_centavos        bigint not null default 0,     -- soma dos Tips do período (recalculado)
  servico_ajuste_centavos     bigint not null default 0,     -- lançamento manual (±)
  servico_bruto_centavos      bigint not null default 0,     -- greatest(0, zig + ajuste)
  percentual_retencao         numeric(5,2) not null check (percentual_retencao between 0 and 100),
  retencao_centavos           bigint not null default 0,
  base_distribuivel_centavos  bigint not null default 0,
  proporcional_dias           boolean not null default false,
  dias_periodo                int not null default 0,
  soma_pontos_efetivos        numeric(18,6) not null default 0,
  valor_ponto_centavos        numeric(18,6),                 -- null se soma = 0
  observacoes                 text,
  criado_por                  uuid references public.perfis (id) on delete set null,
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),
  calculado_em                timestamptz,
  fechado_por                 uuid references public.perfis (id) on delete set null,
  fechado_em                  timestamptz,
  constraint comissao_periodo check (data_fim >= data_inicio and data_fim - data_inicio <= 92)
);
create table if not exists public.comissao_itens (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references public.empresas (id) on delete cascade,
  fechamento_id     uuid not null references public.comissao_fechamentos (id) on delete cascade,
  funcionario_id    uuid references public.funcionarios (id) on delete set null,   -- snapshot sobrevive
  funcionario_nome  text not null,       -- snapshot
  cargo             text,                -- snapshot
  incluido          boolean not null default true,
  pontos            numeric(8,2) not null check (pontos >= 0),
  dias_trabalhados  int not null default 0,
  pontos_efetivos   numeric(18,6) not null default 0,
  valor_centavos    bigint not null default 0,
  criado_em         timestamptz not null default now(),
  unique (fechamento_id, funcionario_id)
);
-- índices por FK. Ambas '[api:leitura]'. Gatilho: fechamento 'fechado' (e seus itens) não aceita UPDATE/DELETE
-- de ninguém, nem do master → erro 'Fechamento já está fechado'. (Exclusão da empresa inteira em cascata é permitida:
-- o gatilho deixa passar quando a empresa não existe mais / pg_trigger_depth() > 1 em cascata.)
```

---

## 7. Ponto: apuração, alarmes e banco de horas (backend-2)

### 7.1 Fonte das batidas
Tudo normalizado em `ponto_batidas`:
- `controlid_acesso`: `access_logs` de iDAccess/iDFace/iDFlex. Só eventos válidos (padrão `[7]` = acesso concedido; configurável em
  `parametros.eventos_validos`). Funcionário resolvido por `controlid_usuarios(integracao_id, user_id_externo = user_id).funcionario_id`.
- `controlid_rep`: marcações (registro tipo 3) do AFD do iDClass. Funcionário resolvido por `funcionarios.cpf` ou `funcionarios.pis`
  (só dígitos) na mesma empresa.
- `manual`: incluída pelo gerente via `ponto_incluir_batida` (motivo obrigatório; auditada em `ponto_ajustes`).
Sem funcionário resolvido → grava com `funcionario_id null` (não entra na apuração) e aparece no painel como
"batidas sem funcionário vinculado". Quando o vínculo surge, os gatilhos do §7.8 preenchem e reapuram.

### 7.2 Cálculo de um dia — `ponto_calcular_dia(p_funcionario uuid, p_data date)` (`[interno]`, `stable`)
Não grava nada. Fonte única da verdade usada por `ponto_apurar` e `ponto_espelho`. Passos, para o funcionário F e o dia de trabalho D:

1. **Fora do vínculo**: se `D < data_admissao` ou `D > data_desligamento` → não apurar (sem linha, sem alarmes).
2. **Escala**: `jornada` = vigente em D (§5 `funcionario_jornadas`); `jd` = `jornada_dias` com `dia_semana = extract(dow from D)`.
   **Abono**: `ponto_abonos` de F em D, senão o da empresa (funcionario_id null) em D.
   - Abono → `previsto = 0`, `esperadas = 0`, `abono_tipo` = tipo.
   - Sem jornada vigente → `previsto = 0`, `esperadas = 0` (situação base `sem_escala`).
   - Jornada sem `jd` no dia → folga: `previsto = 0`, `esperadas = 0`.
   - Senão `previsto = jd.minutos_previstos`, `esperadas = jd.batidas_esperadas` (2 ou 4).
3. **Batidas**: `ponto_batidas` de F com `data_trabalho = D` e `desconsiderada = false`, ordenadas por `instante, id`.
   **Duplicadas**: uma batida a menos de `empresas.ponto_janela_duplicada_minutos` (padrão 2) da última batida **válida** é
   duplicada (ignorada). `n` = nº de válidas.
4. **Trabalhado**: pares (1ª,2ª), (3ª,4ª)…; `trabalhado = Σ floor(extract(epoch from (b2 − b1)) / 60)`. Com `n` ímpar a última fica sem par
   e não conta.
5. **Saldo**: `bruto = trabalhado − previsto`. Se `previsto > 0` e `|bruto| ≤ jornada.tolerancia_diaria_minutos` → `saldo = 0`; senão `saldo = bruto`.
   Dia sem escala/folga/abono com batidas → `saldo = trabalhado` (hora extra). Dia escalado sem batida e encerrado → `saldo = −previsto`.
   Dia **não encerrado** (D ≥ dia de trabalho atual) → `saldo = 0` (provisório; não entra no banco).
6. **Atraso** (`atraso_minutos`): com `esperadas > 0` e `n > 0`: `max(0, floor((primeira − E1)/60s))` se maior que
   `tolerancia_batida_minutos`, senão 0. (E1 = instante previsto da entrada, §2.4.)
7. **Situação** (na ordem):
   `encerrado = false` → `em_andamento`; abono → `abonado`; `esperadas = 0 e n = 0` → `sem_escala` (sem jornada) ou `folga`;
   `n = 0` → `ausente`; `n ≥ esperadas e n par` → `completo`; senão `incompleto`.

### 7.3 Alarmes esperados de um dia
Calculados junto (passo 8 do cálculo). Instantes previstos `E1..Ek` (k = esperadas) = entrada, saida_intervalo, volta_intervalo, saida
(k=4) ou entrada, saida (k=2), convertidos por §2.4.

| tipo | quando (dia **encerrado**, salvo atraso) | `batida_esperada` | `detalhe` (exemplo) |
|---|---|---|---|
| `sem_batida_dia_escalado` | `esperadas > 0` e `n = 0` | `''` | `Nenhuma batida em dia de escala (17:00–01:00)` |
| `batida_faltando` | `0 < n < esperadas`: **um alarme por batida faltante** | slot faltante | `Faltou a volta do intervalo (21:30)` |
| `batidas_impares` | `n` ímpar e **não** (`0 < n < esperadas`) — inclui ímpar em folga/sem escala | `''` | `5 batidas (número ímpar)` |
| `atraso` | `empresas.ponto_alarme_atraso = true`, `atraso_minutos > 0`; vale **também no dia corrente** | `'entrada'` | `Entrada 17:23 (23 min de atraso)` |

**Qual batida faltou** (`0 < n < k`): escolher quais `n` dos `k` slots foram batidos, preservando a ordem, minimizando
`Σ |batida_i − slot_escolhido_i|` (enumeração das combinações C(k,n) — no máximo 6); empate → a combinação lexicograficamente menor
(slots mais cedo). Os slots não escolhidos geram um alarme cada, com `horario_previsto` = instante do slot.
Ex.: escala 17:00/21:00/21:30/01:00, batidas 16:58, 21:02, 01:05 → melhor combinação {1,2,4} → falta `volta_intervalo` (21:30).
Abono no dia → nenhum alarme. Dias fora do vínculo → nenhum alarme.

### 7.4 Persistência — `ponto_apurar(p_funcionario uuid, p_inicio date, p_fim date) returns int` (`[interno]`)
Para cada D em `[p_inicio, least(p_fim, dia_de_trabalho_atual)]` dentro do vínculo: calcula, faz *upsert* em `ponto_dias` e sincroniza
`ponto_alarmes` pela chave `(funcionario_id, data, tipo, batida_esperada)`:
- alarme esperado e inexistente → insere `aberto`;
- esperado e existente `resolvido` **automaticamente** → volta a `aberto` (limpa `resolvido_*`); `justificado` ou `aberto` → mantém o status
  (atualiza `detalhe`, `horario_previsto`, `minutos`);
- existente `aberto` e não mais esperado → `resolvido`, `resolvido_automaticamente = true`, `resolvido_em = agora()`;
- existente `justificado` e não mais esperado → mantém `justificado`.
Depois grava `ponto_dias.alarmes_abertos`. Retorna o número de dias apurados. Dias fora do vínculo: apaga a linha de `ponto_dias` e
resolve automaticamente alarmes abertos.

**Quem chama a apuração**: as RPCs de ingestão (dias afetados), as RPCs manuais de batida/abono, os gatilhos do §7.8,
`ponto_reapurar` (botão "Recalcular") e a rotina diária do N8N (`ingestao_apurar_ponto`, que cria as linhas de dias sem batida e os
alarmes `sem_batida_dia_escalado` de ontem).

### 7.5 Banco de horas
- Saldo de F até a data X (`banco_horas_saldo`):
  - `B` = último `saldo_inicial` de F com `data ≤ X` (se houver): base = `B.minutos`, conta dias e lançamentos **a partir de** `B.data`
    (o saldo inicial é o saldo no **início** do dia `B.data`); sem saldo inicial: base 0, desde sempre.
  - `saldo = base + Σ ponto_dias.saldo_minutos (encerrado, data ∈ [início, X]) + Σ lançamentos ≠ saldo_inicial (data ∈ [início, X])`.
  - `X` padrão = ontem (último dia encerrado).
- Lançamentos (`banco_horas_lancar`): `ajuste` (±), `compensacao` (folga compensada, normalmente −), `pagamento` (horas pagas em folha, −),
  `saldo_inicial` (só administrador; um por funcionário/data).
- Não tratado nesta versão (documentado): hora noturna reduzida, adicional, limites legais de compensação, DSR.

### 7.6 Exemplo numérico (vetor de teste obrigatório em `supabase/testes/20_ponto_apuracao.sql`)
Empresa fuso SP, virada 05:00, janela duplicada 2 min. Jornada "Salão noite" só com sábado (6) 17:00/21:00/21:30/01:00 (previsto 450; demais dias = folga),
tolerância diária 10, tolerância batida 5. Relógio fixo `2026-10-06 12:00-03`.
| D | batidas (local) | n | trabalhado | saldo | situação | alarmes |
|---|---|---|---|---|---|---|
| sáb 2026-10-03 | 16:58, 21:02, 21:29, 01:04 (dom) | 4 | 244+215 = 459 | 0 (|9| ≤ 10) | completo | — |
| sáb 2026-09-26 | 17:20, 17:21 (dup.), 21:00, 21:30, 01:00 | 4 | 220+210 = 430 | −20 | completo | atraso 20 min (se ligado) |
| sáb 2026-09-19 | 16:58, 21:02, 01:05 | 3 | 244 | −206 | incompleto | batida_faltando volta_intervalo |
| sáb 2026-09-12 | — | 0 | 0 | −450 | ausente | sem_batida_dia_escalado |
| dom 2026-09-13 (folga) | 10:00, 12:00, 13:00 | 3 | 120 | +120 | incompleto | batidas_impares |

### 7.7 Ações manuais (RPCs em §10.4)
- Incluir batida: cria `manual`, grava `ponto_ajustes(acao='incluir')`, reapura o dia de trabalho da batida.
- Desconsiderar/restaurar qualquer batida: altera `desconsiderada`/`motivo`, grava ajuste, reapura.
- Editar batida manual = desconsiderar + incluir (o front faz as duas chamadas).
- Justificar alarme: `status = 'justificado'`, `justificativa`, `justificado_por/em`. Não altera saldo. Reabrir: volta a `aberto` e limpa.

### 7.8 Gatilhos que o backend-2 cria em tabelas do backend-1 (no arquivo `…0200_ponto.sql`)
| tabela (b1) | evento | ação |
|---|---|---|
| `controlid_usuarios` | `after update of funcionario_id` | batidas `controlid_acesso` da integração com `pessoa_externa = user_id_externo`: se novo vínculo, preenche `funcionario_id` das que estão null; se desvinculou/trocou, tira das do funcionário antigo (volta a null ou passa ao novo). Reapura dias afetados de ambos. |
| `funcionarios` | `after insert or update of cpf, pis` | batidas `controlid_rep` da empresa sem funcionário com `pessoa_externa` = cpf/pis → vincula e reapura. |
| `funcionarios` | `after update of data_admissao, data_desligamento, ativo` | reapura o funcionário dos últimos 93 dias. |
| `funcionario_jornadas` | `after insert/update/delete` | reapura o funcionário de `vigente_desde` (limitado a 93 dias atrás) até hoje. |
| `jornada_dias`, `jornadas` | `after insert/update/delete` | reapura, nos últimos 31 dias, os funcionários com essa jornada vigente. |
Funcionário inativo (`ativo = false`) **continua** sendo apurado dentro do vínculo (datas); `ativo` só esconde de listas.

---

## 8. Zig: vendas e faturamento (backend-2)

- **Faturamento** = `zig_faturamento` (por `data_operacao`, `payment_name`). É a fonte do "faturamento do dia".
- **Vendas** = `zig_vendas_itens` com `tipo <> 'Tip'`; `valor_total = round(unit_value × quantidade) − discount_value`.
- **Serviço (gorjeta/10%)** = `Σ valor_total` de `zig_vendas_itens` com `tipo = 'Tip'`. `zig_compradores.tip_value` serve só de conferência
  (`servico_compradores` em `vendas_resumo`).
- **Venda por garçom** = agregação de `zig_vendas_itens` por `lower(btrim(employee_name))`; nome exibido = o `employee_name` mais frequente;
  ligação com funcionário por `funcionarios.zig_employee_name` (mesma normalização) **na leitura** (renomear corrige o histórico).
  `employee_name` vazio/null → grupo "(sem garçom)" com `employee_name = null`.
- Datas: sempre `data_operacao` = dia consultado na Zig (o N8N consulta **um dia por vez**, `dtinicio = dtfim`).
- `transactionDate` sem fuso é interpretado no fuso da empresa; com `Z`/offset, como veio.
- `type` desconhecido → `tipo = 'Outro'` (o valor cru vai em `tipo_original`).

---

## 9. Comissão (backend-2; prévia idêntica no front, `web/src/lib/comissao.ts`)

**Regra do cliente**: "pegar o serviço menos 20% e fazer os cálculos em cima dos pontos de comissão de cada funcionário".

Para um fechamento de `[data_inicio, data_fim]` (loja opcional):
1. `servico_zig = Σ valor_total` dos itens `Tip` no período (e loja, se definida).
2. `servico_bruto = max(0, servico_zig + servico_ajuste)` — o ajuste manual (±) cobre serviço pago fora da Zig, estornos etc.
3. `retencao = round(servico_bruto × percentual_retencao / 100)`; `base = servico_bruto − retencao`.
   `percentual_retencao` vem de `empresas.comissao_percentual_retencao` ao criar (padrão 20) e é editável no rascunho.
4. Participantes = itens com `incluido = true`. `pontos` do item: ao criar, `pontos_vigentes(funcionario, data_fim)`; editável no rascunho.
5. `dias_periodo = data_fim − data_inicio + 1`. `dias_trabalhados` = nº de dias de trabalho no período com ao menos uma batida válida
   (`ponto_dias.batidas_validas > 0`).
6. `pontos_efetivos = pontos` (padrão) ou, com `proporcional_dias = true`, `round(pontos × dias_trabalhados / dias_periodo, 6)`.
   Item não incluído → `pontos_efetivos = 0`, `valor = 0`.
7. `soma = Σ pontos_efetivos`. Se `soma = 0` → todos os valores 0 e `valor_ponto_centavos = null` (fechar é recusado: `Fechamento sem participantes`).
8. `valor_ponto = base / soma` (numeric, 6 casas, só para exibir).
9. **Arredondamento (maior resto, determinístico)**: `exato_i = base × pe_i / soma` (numeric sem arredondar);
   `piso_i = floor(exato_i)`; `resto = base − Σ piso_i` (0 ≤ resto < nº de participantes); dá **+1 centavo** a `resto` participantes
   ordenados por: parte fracionária desc, `pontos_efetivos` desc, `funcionario_nome` asc, `funcionario_id` asc.
   Garantia: `Σ valor_centavos = base` exatamente.

**Exemplo (vetor de teste obrigatório no banco e no vitest)**:
serviço Zig R$ 10.000,00 (`1000000`), ajuste −R$ 50,00 (`−5000`) → bruto `995000`; retenção 20% → `199000`; base `796000`.

| funcionário | cargo | pontos | exato (centavos) | piso | fração | +1? | valor |
|---|---|---|---|---|---|---|---|
| Ana Souza | Garçom | 10 | 209473,684211 | 209473 | 0,684 | sim (2º) | **209474** |
| Bruno Lima | Garçom | 10 | 209473,684211 | 209473 | 0,684 | sim (3º, nome) | **209474** |
| Carla Dias | Cumim | 6 | 125684,210526 | 125684 | 0,211 | não | **125684** |
| Davi Rocha | Bartender | 8 | 167578,947368 | 167578 | 0,947 | sim (1º) | **167579** |
| Eva Martins | Cozinha | 4 | 83789,473684 | 83789 | 0,474 | não | **83789** |
| **total** | | **38** | | 795997 | resto 3 | | **796000** |
`valor_ponto = 796000 / 38 = 20947,368421` centavos (R$ 209,47 por ponto).

Com `proporcional_dias = true`, período de 30 dias e Eva com 15 dias trabalhados (demais 30): Eva `pe = 2`, soma = 36,
valor_ponto = 22111,111111; Ana/Bruno 221111,11 → 221111; Carla 132666,67 → 132666; Davi 176888,89 → 176888; Eva 44222,22 → 44222;
Σ pisos = 795998, resto 2 → Davi (0,89) e Carla (0,67): Davi **176889**, Carla **132667** (total 796000).

**Ciclo**: `rascunho` (criar, editar parâmetros/itens, recalcular — cada alteração recalcula tudo) → `fechado` (`comissao_fechar` recalcula
uma última vez, grava `fechado_por/em`; depois disso imutável, inclusive para o master). Rascunho pode ser excluído; fechado não.

---

## 10. RPCs (assinaturas exatas)

Chamada do front: `supabase.rpc('<nome>', { p_...: ... })` (helper tipado `chamarRpc`, §14.6). Chamada do N8N:
`POST {SUPABASE_URL}/rest/v1/rpc/<nome>` com corpo JSON `{ "p_...": ... }`.
Todas as `[api]` de escrita são `security definer` e fazem a checagem de papel explicitamente. As de leitura podem ser
`security definer` + `resolver_empresa`, retornando só dados da empresa resolvida.

### 10.1 Usuários e empresas (backend-1)
| assinatura | etiqueta / quem | regra |
|---|---|---|
| `admin_criar_usuario(p_email text, p_senha text, p_nome text, p_papel text, p_empresa_id uuid, p_funcionario_id uuid default null) returns uuid` | `[api]` A (na própria empresa; papéis administrador/gerente/leitura), M (qualquer empresa) | Cria em `auth.users` (senha bcrypt via `extensions.crypt(p_senha, extensions.gen_salt('bf'))`, e-mail confirmado, colunas de token = `''`) + `auth.identities` (provider `email`) + perfil. `p_papel='master'` só sem JWT (SQL Editor). `p_funcionario_id` tem de ser da mesma empresa. |
| `admin_atualizar_usuario(p_usuario uuid, p_nome text, p_papel text, p_ativo boolean, p_funcionario_id uuid default null) returns void` | `[api]` A (usuários da empresa, não master), M | Ninguém altera o próprio papel/ativo (`Você não pode alterar o próprio papel ou situação`). Não promove a master. |
| `admin_redefinir_senha(p_usuario uuid, p_senha text) returns void` | `[api]` A (empresa, não master), M | mínimo 6 caracteres |
| `admin_excluir_usuario(p_usuario uuid) returns void` | `[api]` A (empresa, não a si, não master), M (não master) | apaga de `auth.users` (cascata no perfil) |
| `atualizar_meu_perfil(p_nome text) returns void` | `[api]` qualquer logado | |
| `criar_minha_empresa(p_nome text, p_cnpj text default null) returns uuid` | `[api]` perfil sem empresa, não master | Exige `configuracao.cadastro_aberto`. Cria a empresa e torna o perfil `administrador` dela. |
| `master_criar_empresa(p_nome text, p_cnpj text, p_admin_email text, p_admin_senha text, p_admin_nome text) returns uuid` | `[api]` M | Empresa + primeiro administrador numa transação. |
| `tornar_master(p_email text) returns void` | `[interno]` | só pelo SQL Editor |

Gatilho em `auth.users` (insert): cria perfil com `nome` = `raw_user_meta_data->>'nome'` ou `'full_name'` ou `'name'` (Google) ou a parte
antes do `@`. Papel/empresa dos metadados **só** quando o insert vem de `admin_criar_usuario`/`master_criar_empresa` (flag de transação
`set_config('app.criando_usuario','1',true)`). E-mail = `configuracao.master_email` e ainda não há master → `master`. Demais → `administrador`
sem empresa (vê nada até `criar_minha_empresa`).

### 10.2 Cadastros, integrações e sincronização (backend-1)
| assinatura | etiqueta / quem | regra |
|---|---|---|
| `dia_de_trabalho(p_instante timestamptz, p_empresa uuid) returns date` | `[api]` | §2.4 |
| `dia_de_trabalho_atual(p_empresa uuid default null) returns date` | `[api]` | `dia_de_trabalho(agora(), resolver_empresa(p_empresa,'ler'))` |
| `pontos_vigentes(p_funcionario uuid, p_data date) returns numeric` | `[api]` G A M | §5 |
| `funcionario_vincular_controlid(p_controlid_usuario uuid, p_funcionario uuid) returns void` | `[api]` G A M | `p_funcionario null` desvincula. Mesma empresa. Se o funcionário já está ligado a outro usuário do mesmo equipamento, o vínculo antigo é removido. `vinculo='manual'`. |
| `integracao_definir_segredos(p_integracao uuid, p_segredos jsonb) returns void` | `[api]` A M | *Merge*: chave com valor string não vazio grava; `null` ou `''` remove. Só chaves permitidas para o tipo (§11.1) → senão `Segredo inválido para este tipo de integração`. |
| `integracao_segredos_preenchidos(p_integracao uuid) returns text[]` | `[api]` G A M | nomes das chaves preenchidas (nunca os valores) |
| `sync_solicitar(p_integracao uuid default null, p_escopo text default 'tudo', p_data_inicio date default null, p_data_fim date default null, p_parametros jsonb default '{}', p_empresa uuid default null) returns integer` | `[api]` G A M | Cria uma solicitação por integração **ativa** alvo (`p_integracao` null = todas as ativas da empresa compatíveis com o escopo; escopos `apurar_ponto`/`exportar_fechamento` não têm integração). Pula alvo que já tem solicitação `pendente`/`em_andamento` com o mesmo escopo. Período máx. 31 dias. Retorna quantas criou. Solicitação `em_andamento` há mais de 30 min é marcada `erro` ('Expirada') antes. |
| `ingestao_controlid_usuarios(p_integracao uuid, p_usuarios jsonb) returns jsonb` | `[servico]` | §11.3 |
| `ingestao_integracoes_ativas(p_tipo text default null, p_somente_vencidas boolean default false) returns table(integracao_id uuid, empresa_id uuid, tipo text, nome text, intervalo_minutos int, ultima_execucao_em timestamptz)` | `[servico]` | integrações `ativa` de empresas `ativa`; vencida = `ultima_execucao_em is null or agora() − ultima_execucao_em ≥ intervalo_minutos` |
| `ingestao_integracao_config(p_integracao uuid) returns jsonb` | `[servico]` | `{integracao_id, empresa_id, tipo, nome, ativa, parametros, segredos, cursor, fuso, virada_dia, dia_trabalho_atual, lojas:[{loja_id_externo,nome,sincronizar}]}` (`lojas` só zig, lido de `zig_lojas` se existir) |
| `ingestao_funcionarios_para_exportar(p_integracao uuid) returns table(funcionario_id uuid, nome text, registration text, cpf text, pis text)` | `[servico]` | funcionários ativos da empresa, dentro do vínculo, **sem** `controlid_usuarios` ligado nesse equipamento; `registration = matricula` |
| `ingestao_sync_pegar_solicitacoes(p_limite int default 5) returns table(solicitacao_id uuid, empresa_id uuid, integracao_id uuid, integracao_tipo text, escopo text, data_inicio date, data_fim date, parametros jsonb)` | `[servico]` | `pendente` mais antigas, `for update skip locked`, passa a `em_andamento` + `pego_em` |
| `ingestao_sync_concluir_solicitacao(p_solicitacao uuid, p_status text, p_mensagem text default null, p_execucao uuid default null) returns void` | `[servico]` | `p_status ∈ {concluida, erro}` |
| `ingestao_sync_iniciar(p_tipo text, p_gatilho text, p_workflow text, p_empresa uuid default null, p_integracao uuid default null, p_solicitacao uuid default null, p_periodo_inicio date default null, p_periodo_fim date default null, p_n8n_execution_id text default null) returns uuid` | `[servico]` | cria `sync_execucoes` 'executando'; marca como `erro` ('Expirada') execuções 'executando' há > 30 min da mesma integração+tipo; `integracoes.ultima_execucao_em = agora()`; `empresa_id` derivado da integração se null |
| `ingestao_sync_finalizar(p_execucao uuid, p_status text, p_lidos int default 0, p_gravados int default 0, p_ignorados int default 0, p_erro text default null, p_detalhes jsonb default '{}', p_tentativas int default 1) returns void` | `[servico]` | `p_status ∈ {sucesso, parcial, erro}`; atualiza `integracoes.ultimo_status/ultimo_erro` e, se sucesso/parcial, `ultimo_sucesso_em` |

### 10.3 Tarefas (backend-1)
| assinatura | quem | regra |
|---|---|---|
| `tarefas_gerar_do_dia(p_data date default null, p_empresa uuid default null) returns integer` | `[api]` L G A M | Materializa as rotinas ativas que caem em `p_data` (padrão: dia de trabalho atual) em `tarefas` + `tarefa_itens`, idempotente por `unique(rotina_id, data)`. Retorna quantas criou. O front chama ao abrir Painel/Tarefas. |
| `ingestao_tarefas_gerar(p_data date default null) returns integer` | `[servico]` | idem para todas as empresas ativas (data padrão por empresa) |
| `tarefa_mudar_status(p_tarefa uuid, p_status text) returns void` | `[api]` G A M; L só se responsável | |
| `tarefa_marcar_item(p_item uuid, p_feito boolean) returns void` | `[api]` G A M; L só se responsável pela tarefa | |

Responsável (leitura): `tarefas.responsavel_perfil_id = auth.uid()` ou `responsavel_funcionario_id = meu_funcionario()`.

### 10.4 Ponto e banco de horas (backend-2)
| assinatura | quem | regra |
|---|---|---|
| `ponto_espelho(p_funcionario uuid, p_inicio date, p_fim date) returns table(data date, dia_semana smallint, situacao text, encerrado boolean, abono_tipo text, jornada_nome text, previsto_minutos int, trabalhado_minutos int, saldo_minutos int, atraso_minutos int, batidas jsonb, alarmes jsonb, esperadas jsonb)` | `[api]` L G A M | Máx. 62 dias. Calcula ao vivo (`ponto_calcular_dia`); dias fora do vínculo são omitidos. `batidas`: `[{id, instante, origem, desconsiderada, duplicada, motivo}]` (inclui desconsideradas, ordenadas). `alarmes`: `[{id, tipo, batida_esperada, status, detalhe, justificativa}]` (da tabela). `esperadas`: `[{batida:'entrada'|..., instante}]`. |
| `ponto_dia_empresa(p_data date default null, p_empresa uuid default null) returns table(funcionario_id uuid, funcionario_nome text, cargo text, situacao text, encerrado boolean, previsto_minutos int, trabalhado_minutos int, saldo_minutos int, atraso_minutos int, batidas jsonb, alarmes_abertos int)` | `[api]` L G A M | Todos os funcionários no vínculo na data (padrão: dia atual), ao vivo. Ordem por nome. |
| `ponto_reapurar(p_inicio date, p_fim date, p_funcionario uuid default null, p_empresa uuid default null) returns integer` | `[api]` G A M | máx. 93 dias; todos os funcionários da empresa se `p_funcionario` null |
| `ponto_incluir_batida(p_funcionario uuid, p_instante timestamptz, p_motivo text) returns uuid` | `[api]` G A M | motivo obrigatório; instante não pode ser futuro (`Horário no futuro`) |
| `ponto_desconsiderar_batida(p_batida uuid, p_motivo text) returns void` | `[api]` G A M | |
| `ponto_restaurar_batida(p_batida uuid, p_motivo text) returns void` | `[api]` G A M | |
| `ponto_justificar_alarme(p_alarme uuid, p_justificativa text) returns void` | `[api]` G A M | justificativa obrigatória |
| `ponto_reabrir_alarme(p_alarme uuid) returns void` | `[api]` G A M | |
| `ponto_abonar(p_inicio date, p_fim date, p_tipo text, p_motivo text default null, p_funcionario uuid default null, p_empresa uuid default null) returns integer` | `[api]` G A M | um abono por dia (upsert); `p_funcionario` null = empresa toda; máx. 62 dias; reapura; retorna dias |
| `ponto_remover_abono(p_abono uuid) returns void` | `[api]` G A M | reapura |
| `banco_horas_saldo(p_funcionario uuid, p_ate date default null) returns bigint` | `[api]` L G A M | §7.5 |
| `banco_horas_resumo(p_ate date default null, p_empresa uuid default null) returns table(funcionario_id uuid, funcionario_nome text, cargo text, saldo_minutos bigint, saldo_mes_minutos bigint, ultimo_dia_apurado date)` | `[api]` L G A M | funcionários ativos; `saldo_mes` = soma de dias+lançamentos do mês de `p_ate` |
| `banco_horas_extrato(p_funcionario uuid, p_inicio date, p_fim date) returns table(data date, tipo text, descricao text, minutos int, saldo_acumulado bigint, referencia_id uuid)` | `[api]` L G A M | 1ª linha `tipo='saldo_anterior'` (data = p_inicio − 1); depois, por data, `tipo='dia'` (dias encerrados com saldo ≠ 0 ou situação ≠ folga) e `tipo=<tipo do lançamento>`; dias antes de lançamentos no mesmo dia. Máx. 366 dias. |
| `banco_horas_lancar(p_funcionario uuid, p_data date, p_tipo text, p_minutos integer, p_motivo text) returns uuid` | `[api]` G A M; `saldo_inicial` só A M | |
| `banco_horas_excluir_lancamento(p_lancamento uuid) returns void` | `[api]` A M | |

### 10.5 Vendas (backend-2)
Todas `[api]` L G A M, período máx. 366 dias, `p_loja text default null` (null = todas), `p_empresa uuid default null`.
| assinatura | retorno |
|---|---|
| `vendas_resumo(p_inicio date, p_fim date, p_loja text default null, p_empresa uuid default null)` | `table(faturamento bigint, vendas bigint, servico bigint, descontos bigint, transacoes bigint, servico_compradores bigint)` — 1 linha, zeros se vazio |
| `vendas_faturamento_por_dia(...)` (mesmos parâmetros) | `table(data date, valor bigint)` — um registro por dia do período (dias sem dado = 0) |
| `vendas_faturamento_por_forma(...)` | `table(payment_id int, payment_name text, valor bigint)` ordem valor desc |
| `vendas_por_garcom(...)` | `table(employee_name text, funcionario_id uuid, funcionario_nome text, quantidade numeric, valor_vendas bigint, valor_servico bigint, transacoes bigint)` ordem `valor_vendas` desc; `transacoes` = nº de `transaction_id` distintos |

### 10.6 Comissões (backend-2)
| assinatura | quem | regra |
|---|---|---|
| `comissao_criar_fechamento(p_data_inicio date, p_data_fim date, p_titulo text default null, p_loja text default null, p_proporcional_dias boolean default false, p_empresa uuid default null) returns uuid` | G A M | cria rascunho com itens de todos os funcionários `ativo`, `participa_comissao`, no vínculo em algum dia do período e com `pontos_vigentes > 0`; calcula |
| `comissao_atualizar_fechamento(p_fechamento uuid, p_titulo text, p_servico_ajuste_centavos bigint, p_percentual_retencao numeric, p_proporcional_dias boolean, p_observacoes text) returns void` | G A M | só rascunho; recalcula |
| `comissao_definir_item(p_fechamento uuid, p_funcionario uuid, p_pontos numeric, p_incluido boolean default true) returns void` | G A M | *upsert* do item (snapshot de nome/cargo); recalcula |
| `comissao_remover_item(p_fechamento uuid, p_funcionario uuid) returns void` | G A M | recalcula |
| `comissao_recalcular(p_fechamento uuid) returns void` | G A M | relê serviço e presença; §9 |
| `comissao_fechar(p_fechamento uuid) returns void` | A M | recalcula e fecha |
| `comissao_excluir_rascunho(p_fechamento uuid) returns void` | G A M | |
Leitura: `comissao_fechamentos` e `comissao_itens` direto (RLS G A M).

### 10.7 Painel (backend-2)
`painel_do_dia(p_empresa uuid default null) returns jsonb` — `[api]` L G A M. Formato exato (TS `PainelDoDia`, §14.6):
```json
{
  "empresa_id": "uuid", "dia_trabalho": "2026-10-06", "ontem": "2026-10-05",
  "faturamento": { "hoje": 0, "ontem": 0, "mes": 0, "tem_zig": true },
  "servico": { "ontem": 0, "mes": 0 },
  "ponto": {
    "alarmes_abertos": 3,
    "alarmes": [ { "id": "uuid", "funcionario_id": "uuid", "funcionario_nome": "Ana Souza", "data": "2026-10-05",
                   "tipo": "batida_faltando", "batida_esperada": "volta_intervalo", "detalhe": "Faltou a volta do intervalo (21:30)" } ],
    "presentes_agora": 4, "escalados_hoje": 5, "batidas_sem_funcionario": 0
  },
  "tarefas": { "total": 8, "concluidas": 3, "pendentes": 5, "atrasadas": 1 },
  "sincronizacao": [ { "integracao_id": "uuid", "tipo": "zig", "nome": "Zig", "ativa": true, "ultimo_sucesso_em": "ISO|null",
                       "ultimo_status": "sucesso|parcial|erro|null", "ultimo_erro": null, "executando": false } ]
}
```
`alarmes`: os 5 abertos mais recentes (data desc). `presentes_agora`: funcionários com nº ímpar de batidas válidas hoje.
`escalados_hoje`: com `esperadas > 0` hoje. `executando`: existe `sync_execucoes` 'executando' ou solicitação `pendente`/`em_andamento` da integração.
`sincronizacao`: todos os papéis veem (só status, nunca segredos).

### 10.8 Ingestão e exportação (backend-2, `[servico]`)
`ingestao_controlid_batidas`, `ingestao_zig_lojas`, `ingestao_zig_saida_produtos`, `ingestao_zig_faturamento`,
`ingestao_zig_faturamento_bandeiras`, `ingestao_zig_compradores`, `ingestao_apurar_ponto`, `ingestao_fechamento_exportar` — §11.

### 10.9 Mensagens de erro (texto exato)
`Sem permissão` · `Informe a empresa` · `Empresa não encontrada` · `Período inválido` · `Período máximo de N dias` (N numérico) ·
`Funcionário não encontrado` · `Funcionário de outra empresa` · `Jornada de outra empresa` · `Horários da jornada fora de ordem` ·
`Informe o motivo` · `Informe a justificativa` · `Horário no futuro` · `Batida não encontrada` · `Alarme não encontrado` ·
`Fechamento não encontrado` · `Fechamento já está fechado` · `Fechamento sem participantes` · `Somente o administrador fecha a comissão` ·
`E-mail já cadastrado` · `E-mail inválido` · `A senha deve ter pelo menos 6 caracteres` · `Informe o nome` · `Papel inválido` ·
`Você não pode excluir a si mesmo` · `Você não pode alterar o próprio papel ou situação` · `Você já pertence a uma empresa` ·
`Cadastro de novas empresas desativado` · `Segredo inválido para este tipo de integração` · `Integração não encontrada` ·
`Integração inativa` · `Tipo de integração incompatível` · `Loja não encontrada` · `Fuso horário inválido` · `Tarefa não encontrada`.

---

## 11. Integrações: parâmetros, segredos e payloads de ingestão

### 11.1 `integracoes.parametros` (visível) e `integracoes_segredos.segredos` (oculto)
| tipo | `parametros` (padrões) | `segredos` (chaves permitidas) |
|---|---|---|
| `zig` | `{"rede": "<id da rede>", "dias_retroativos": 2}` | `{"token": "<token da Zig>"}` |
| `controlid_acesso` | `{"modelo": "iDFace", "dias_retroativos": 2, "eventos_validos": [7], "relogio_em_hora_local": true}` | `{"url": "http://192.168.0.50", "login": "admin", "senha": "admin"}` |
| `controlid_rep` | `{"modelo": "iDClass", "dias_retroativos": 2, "identificador": "cpf"}` (`"cpf"` Portaria 671 / `"pis"` legado) | `{"url": "https://192.168.0.60", "login": "admin", "senha": "admin"}` |

`relogio_em_hora_local = true` (padrão): o `time` (unix) dos `access_logs` representa a **hora de parede local** gravada como se fosse UTC
(comportamento comum dos equipamentos); o N8N envia `instante_local`. `false`: envia `instante` UTC. Confirmar com uma batida conhecida na implantação.
**Rede**: o N8N tem de alcançar o IP do equipamento (N8N instalado na rede da loja, VPN ou redirecionamento de porta). O RHiD/iDSecure
(nuvem) fica como evolução futura (tipo reservado `controlid_rhid`, não implementado).

`integracoes.cursor` (escrito só pelas RPCs de ingestão):
- `controlid_acesso`: `{"ultimo_id": "123", "ultimo_instante": "ISO"}`; `controlid_rep`: `{"ultimo_nsr": 456, "ultimo_instante": "ISO"}`;
- `zig`: `{"ultimo_dia": "2026-10-05"}` (gravado por `ingestao_zig_saida_produtos`).

### 11.2 Formato comum do retorno das ingestões
Todas retornam `jsonb` com pelo menos `{"lidos": int, "gravados": int, "ignorados": int}` + campos específicos abaixo. Erros de
validação do lote inteiro → exceção (o N8N registra `erro`); itens individuais inválidos → contam em `ignorados` com
`"erros": [{"indice": 3, "motivo": "instante inválido"}]` (máx. 20 itens listados). Todas validam que a integração existe, está ativa e é
do tipo certo (`Integração não encontrada`, `Integração inativa`, `Tipo de integração incompatível`).

### 11.3 `ingestao_controlid_usuarios(p_integracao uuid, p_usuarios jsonb) returns jsonb` (backend-1)
`p_usuarios` = **lista completa** de usuários do equipamento:
```json
[ { "id": "12", "registration": "3", "name": "CARLA DIAS", "cpf": null, "pis": null } ]
```
(acesso: `id` = `users.id`; REP: `id` = CPF ou PIS só dígitos, conforme `parametros.identificador`). Upsert por
`(integracao_id, user_id_externo)`; atualiza `visto_em`, `removido_no_equipamento = false`; quem não veio → `removido_no_equipamento = true`.
**Vínculo automático** (só se `funcionario_id` null e o funcionário não está ligado a outro usuário desse equipamento), na ordem:
1) `registration = funcionarios.matricula`; 2) CPF igual; 3) PIS igual — sempre na mesma empresa e com resultado único → `vinculo='automatico'`.
Nunca desfaz vínculo manual. Retorno: `{lidos, gravados, ignorados, inseridos, atualizados, removidos, vinculados_automaticamente, sem_vinculo}`.

### 11.4 `ingestao_controlid_batidas(p_integracao uuid, p_batidas jsonb) returns jsonb` (backend-2)
Lote de até 2000 itens. Origem = tipo da integração.
```json
[
  { "id_externo": "98123", "instante_local": "2026-10-05T17:02:11", "user_id": "12", "evento": 7 },
  { "id_externo": "98124", "instante": "2026-10-05T20:02:11Z", "user_id": "12", "evento": 7 },
  { "id_externo": "4567", "nsr": 4567, "instante": "2026-10-05T17:02:00-03:00", "cpf": "52998224725" },
  { "id_externo": "4568", "nsr": 4568, "instante_local": "2026-10-05T21:30:00", "pis": "12345678901" }
]
```
Regras: exatamente um de `instante` (ISO com fuso) ou `instante_local` (sem fuso, interpretado em `empresas.fuso`);
acesso: `evento` presente e fora de `parametros.eventos_validos` → ignorado; `user_id` vazio/"0" → ignorado. `pessoa_externa` = `user_id`
(acesso) ou `cpf`/`pis` (REP). Insert `on conflict (integracao_id, id_externo) do nothing` (batida já existente nunca é alterada).
Resolve funcionário (§7.1); apura **cada (funcionário, data_trabalho) afetado** uma vez; atualiza `integracoes.cursor`
(máximo de id/NSR e instante). Retorno: `{lidos, gravados, ignorados, duplicados, sem_funcionario, dias_apurados, cursor}`.

### 11.5 Zig (backend-2) — o N8N repassa o JSON da API **sem transformar**
| RPC | `p_itens` = resposta de | idempotência |
|---|---|---|
| `ingestao_zig_lojas(p_integracao uuid, p_lojas jsonb) returns jsonb` | `/erp/lojas` `[{id, name}]` | upsert `(empresa_id, loja_id_externo)`; `nome` atualizado; `sincronizar` preservado (novas = true) |
| `ingestao_zig_saida_produtos(p_integracao uuid, p_loja text, p_data date, p_itens jsonb) returns jsonb` | `/erp/saida-produtos` | **substitui o dia**: apaga `(empresa, loja, data_operacao = p_data)` e insere o lote, na mesma transação |
| `ingestao_zig_faturamento(p_integracao uuid, p_loja text, p_data date, p_itens jsonb) returns jsonb` | `/erp/faturamento` | substitui o dia |
| `ingestao_zig_faturamento_bandeiras(p_integracao uuid, p_loja text, p_data date, p_itens jsonb) returns jsonb` | `/erp/faturamento/detalhesMaquinaIntegrada` (cada `values[]` vira uma linha) | substitui o dia |
| `ingestao_zig_compradores(p_integracao uuid, p_loja text, p_data date, p_itens jsonb) returns jsonb` | `/erp/compradores` (descarta `userDocument`, `userDocumentType`, `userPhone`, `userName`, `userEmail`) | substitui o dia |

Mapeamento de `saida-produtos`: `transactionId→transaction_id`, `transactionDate→transaction_date` (§8), `productId→product_id`,
`productSku→product_sku`, `unitValue→unit_value`, `count→quantidade`, `fractionalAmount→fractional_amount`, `fractionUnit→fraction_unit`,
`discountValue→discount_value` (null → 0), `productName`, `productCategory`, `eventId→event_id`, `eventDate→event_date` (só a data),
`invoiceId→invoice_id`, `employeeName→employee_name` (btrim; '' → null), `type→tipo`/`tipo_original`, `additions` (null → `[]`).
Ids numéricos viram texto. `p_loja` tem de existir em `zig_lojas` da empresa (`Loja não encontrada`). `p_itens` vazio é válido (dia zerado).
Retorno: `{lidos, gravados, ignorados, removidos}`. `ingestao_zig_saida_produtos` atualiza `cursor.ultimo_dia` = max.

### 11.6 Outras (backend-2)
- `ingestao_apurar_ponto(p_empresa uuid default null, p_inicio date default null, p_fim date default null) returns jsonb` —
  padrão: todas as empresas ativas, `[dia atual − 2, dia atual]`; apura todos os funcionários no vínculo. Retorno `{empresas, funcionarios, dias}`.
- `ingestao_fechamento_exportar(p_fechamento uuid) returns jsonb` —
  `{"fechamento": {…colunas de comissao_fechamentos…, "empresa_nome": "…"}, "itens": [{…colunas de comissao_itens…}]}` (itens por nome).

---

## 12. Sincronização e N8N

### 12.1 Fluxo
```
[front] botão "Sincronizar agora" ──rpc sync_solicitar──▶ sync_solicitacoes (pendente)
[N8N "MDG · Sincronizar agora (fila)"] a cada 1 min ──ingestao_sync_pegar_solicitacoes──▶ (em_andamento)
      └─ Execute Workflow (subfluxo do tipo) ─▶ ingestao_sync_iniciar → APIs externas → ingestao_* → ingestao_sync_finalizar
      └─ ingestao_sync_concluir_solicitacao(concluida|erro)
[N8N "MDG · Agendador"] a cada 15 min ──ingestao_integracoes_ativas(p_somente_vencidas=true)──▶ mesmo subfluxo, gatilho 'agendado'
[N8N "MDG · Rotina diária"] 05:30 (America/Sao_Paulo) ──ingestao_apurar_ponto + ingestao_tarefas_gerar
```
O front acompanha por `sync_solicitacoes` (status) e `sync_execucoes` (resultado), consultando a cada 5 s enquanto houver pendência.

### 12.2 Chamando o Supabase do N8N
Nó HTTP Request: `POST {{$env.SUPABASE_URL}}/rest/v1/rpc/<rpc>`, cabeçalhos `apikey: {{$env.SUPABASE_SERVICE_ROLE_KEY}}`,
`Authorization: Bearer {{$env.SUPABASE_SERVICE_ROLE_KEY}}`, `Content-Type: application/json`; corpo JSON com os `p_*`.
Exige `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`. Retentativas: nós HTTP com *Retry On Fail* (3 tentativas, 5 s) para Supabase;
(3 tentativas, 10 s) para Zig/Control iD. Ao esgotar: `ingestao_sync_finalizar(status='erro', erro=<mensagem>)`.

Variáveis do N8N (`n8n/.env.example`):
`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `ZIG_BASE_URL` (padrão `https://api.zigcore.com.br/integration`; no teste, o mock),
`MDG_WF_CONTROLID_USUARIOS`, `MDG_WF_CONTROLID_BATIDAS`, `MDG_WF_CONTROLID_EXPORTAR`, `MDG_WF_ZIG_IMPORTAR`, `MDG_WF_EXPORTAR_FECHAMENTO`
(ids dos subfluxos após importar), `MDG_EMAIL_RELATORIOS` (destino do CSV), `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`, `GENERIC_TIMEZONE=America/Sao_Paulo`.

### 12.3 Workflows (arquivos, nomes e dono)
| arquivo | nome no N8N | dono | gatilhos |
|---|---|---|---|
| `n8n/controlid/workflows/controlid-importar-usuarios.json` | `MDG · Control iD · Importar usuários` | n8n-1 | Execute Workflow Trigger |
| `n8n/controlid/workflows/controlid-importar-batidas.json` | `MDG · Control iD · Importar batidas` | n8n-1 | Execute Workflow Trigger |
| `n8n/controlid/workflows/controlid-exportar-usuarios.json` | `MDG · Control iD · Exportar funcionários` | n8n-1 | Execute Workflow Trigger |
| `n8n/zig/workflows/zig-importar.json` | `MDG · Zig · Importar` | n8n-2 | Execute Workflow Trigger |
| `n8n/comum/workflows/sincronizar-agora.json` | `MDG · Sincronizar agora (fila)` | n8n-2 | Schedule (1 min) |
| `n8n/comum/workflows/agendador.json` | `MDG · Agendador` | n8n-2 | Schedule (15 min) |
| `n8n/comum/workflows/rotina-diaria.json` | `MDG · Rotina diária` | n8n-2 | Schedule (05:30) |
| `n8n/comum/workflows/exportar-fechamento.json` | `MDG · Exportar fechamento CSV` | n8n-2 | Execute Workflow Trigger |
| `n8n/comum/workflows/erros.json` | `MDG · Tratador de erros` | n8n-2 | Error Trigger (configurado como *Error Workflow* de todos) |

**Entrada de todo subfluxo** (item JSON do Execute Workflow Trigger):
```json
{ "integracao_id": "uuid|null", "empresa_id": "uuid", "tipo": "zig|controlid_acesso|controlid_rep|null",
  "escopo": "tudo|funcionarios|batidas|vendas|exportar_funcionarios|exportar_fechamento",
  "gatilho": "agendado|manual", "solicitacao_id": "uuid|null",
  "data_inicio": "YYYY-MM-DD|null", "data_fim": "YYYY-MM-DD|null", "parametros": {} }
```
**Saída** (último nó): `{ "execucao_ids": ["uuid"], "status": "sucesso|parcial|erro", "lidos": 0, "gravados": 0, "ignorados": 0, "erro": null }`.
Todo subfluxo: lê a configuração com `ingestao_integracao_config`; abre/fecha **uma** `sync_execucoes` por `tipo` de execução (§5) que realizar.

Despacho (n8n-2) por `tipo`/`escopo`:
| tipo \ escopo | `tudo` | `funcionarios` | `batidas` | `vendas` | `exportar_funcionarios` |
|---|---|---|---|---|---|
| `controlid_acesso`/`_rep` | USUARIOS depois BATIDAS | USUARIOS | BATIDAS | — | EXPORTAR (só acesso) |
| `zig` | ZIG_IMPORTAR | — | — | ZIG_IMPORTAR | — |
`apurar_ponto` → chama `ingestao_apurar_ponto(p_empresa)` direto; `exportar_fechamento` → EXPORTAR_FECHAMENTO. Agendado = escopo `tudo`.

### 12.4 Control iD (n8n-1)
**Acesso (iDAccess/iDFace/iDFlex)** — `{url}` dos segredos:
1. `POST {url}/login.fcgi` `{"login","password"}` → `{"session":"…"}`.
2. Usuários: `POST {url}/load_objects.fcgi?session=S` `{"object":"users"}` → `{"users":[{id, registration, name,…}]}` →
   `ingestao_controlid_usuarios` com `[{id: String(id), registration, name}]`.
3. Batidas: `POST {url}/load_objects.fcgi?session=S` `{"object":"access_logs","where":{"access_logs":{"time":{">=":T}}}}` com
   `T = max(cursor.ultimo_instante − 1 dia, hoje − dias_retroativos)` em unix (no mesmo referencial do relógio — ver `relogio_em_hora_local`);
   sem cursor: `hoje − dias_retroativos`. Paginar com `"limit": 1000, "offset": n` se o equipamento aceitar. Cada log →
   `{id_externo: String(id), user_id: String(user_id), evento: event, instante_local|instante}`; envia em lotes de ≤ 1000.
4. Exportar: `ingestao_funcionarios_para_exportar` → `POST {url}/create_objects.fcgi?session=S`
   `{"object":"users","values":[{"name": nome, "registration": matricula}]}` → em seguida reimporta usuários (vínculo automático pela matrícula).
5. `POST {url}/logout.fcgi?session=S` sempre (também no erro).

**REP (iDClass)**:
1. `POST {url}/login.fcgi` `{"login","password"}` → `{"session"}`.
2. Usuários: `POST {url}/load_users.fcgi?session=S` `{}` → `{"users":[{name, pis|cpf, registration,…}]}` → ingestão com `id` = cpf/pis (dígitos).
3. AFD: `POST {url}/get_afd.fcgi?session=S` com `{"initial_nsr": cursor.ultimo_nsr + 1}`; sem cursor
   `{"initial_date": {"day": d, "month": m, "year": a}}` (hoje − dias_retroativos). Resposta: texto AFD.
4. Parser AFD (`n8n/controlid/lib/afd.mjs`, função `lerAfd(texto) → {marcacoes, ignoradas}`), só registros tipo **3**:
   - **Portaria 671** (50 colunas): `1–9` NSR · `10` tipo `3` · `11–34` data-hora `AAAA-MM-DDThh:mm:00-0300` · `35–46` CPF (12, zero à esquerda) · `47–50` CRC-16.
     → `{id_externo: String(nsr), nsr, instante: "AAAA-MM-DDThh:mm:00-03:00", cpf: <11 dígitos>}`.
   - **Portaria 1510 (legado)** (34 colunas): `1–9` NSR · `10` tipo `3` · `11–18` data `DDMMAAAA` · `19–22` hora `hhmm` · `23–34` PIS (12).
     → `{id_externo: String(nsr), nsr, instante_local: "AAAA-MM-DDThh:mm:00", pis: <11 dígitos>}`.
   - Detecção por linha: caractere 10 = `3` e (caractere 21 = `T` → 671; senão comprimento ≥ 34 → 1510). Demais tipos (1, 2, 4, 5, 6, 7, 9…) ignorados.
     Linhas com `\r\n` aceitas. CRC não validado (documentado).

### 12.5 Zig (n8n-2)
Para a integração: `GET {ZIG_BASE_URL}/erp/lojas?rede={rede}` → `ingestao_zig_lojas`; para cada loja com `sincronizar` e cada dia
`d ∈ [data_inicio, data_fim]` (padrão `[dia_trabalho_atual − dias_retroativos, dia_trabalho_atual]`, máx. 31):
`GET /erp/saida-produtos?dtinicio=d&dtfim=d&loja=L` → `ingestao_zig_saida_produtos`; `GET /erp/faturamento?...` → `ingestao_zig_faturamento`;
`GET /erp/compradores?...` → `ingestao_zig_compradores`; `GET /erp/faturamento/detalhesMaquinaIntegrada?...` → `ingestao_zig_faturamento_bandeiras`.
Cabeçalho `Authorization: {token}` (sem "Bearer"). Pausa de 300 ms entre chamadas. Uma `sync_execucoes` tipo `zig_importar` por execução,
com `detalhes = {"lojas": n, "dias": n, "por_endpoint": {"saida_produtos": {...}, ...}}`; falha em parte dos dias → `parcial`.

### 12.6 Mocks locais (n8n-2) — `node n8n/mocks/servidor.mjs`
| porta | imita | credenciais | comportamento |
|---|---|---|---|
| 54340 | Zig (`/integration/erp/...`) | `Authorization: token-mock` (senão 401) | loja `{"id":"loja-1","name":"Bossa Nova Salão"}` para `rede=rede-mock`; dados determinísticos por data (garçons `Ana Souza`, `Bruno Lima`, `Davi Rocha` + linhas `Tip`; formas Crédito/Débito/Pix/Dinheiro) |
| 54341 | Control iD acesso | `admin`/`admin`, sessão `sessao-mock` | `users` ids 1–5 com `registration` "1"–"5" (nomes dos funcionários demo); `access_logs` evento 7 nos horários da escala dos últimos 7 dias, faltando a volta do intervalo da Carla anteontem; `create_objects` devolve `{"ids":[…]}` |
| 54342 | Control iD REP | `admin`/`admin` | `load_users` com CPFs dos demo; `get_afd` em layout 671 respeitando `initial_nsr` |
`ZIG_BASE_URL=http://127.0.0.1:54340/integration`. Os segredos da carga demo local apontam para estes endereços (§15).

---

## 13. Exportação CSV (formato único — front e N8N)

UTF-8 **com BOM**, separador `;`, fim de linha `\r\n`, aspas duplas quando o campo tiver `;`, `"` ou quebra de linha (aspas internas dobradas).
Dinheiro com vírgula decimal e sem separador de milhar (`2094,74`); datas `dd/mm/aaaa`; minutos como `hh:mm` com sinal (`-03:26`).
Nome do arquivo: `<tipo>_<empresa-slug>_<aaaa-mm-dd>[_<aaaa-mm-dd>].csv`.

| arquivo | colunas |
|---|---|
| `comissao_…` | `Funcionário;Cargo;Incluído;Pontos;Dias trabalhados;Pontos efetivos;Valor (R$)` + linha final `Total;;;<soma pontos>;;<soma pe>;<base>` + bloco de cabeçalho antes das colunas: `Período;dd/mm/aaaa a dd/mm/aaaa`, `Serviço Zig (R$)`, `Ajuste (R$)`, `Serviço bruto (R$)`, `Retenção (%)`, `Retenção (R$)`, `Base distribuível (R$)`, `Valor do ponto (R$)`, `Status`, linha em branco |
| `ponto_…` (espelho) | `Data;Dia;Batidas;Previsto;Trabalhado;Saldo;Situação;Alarmes` (batidas `hh:mm` separadas por espaço) |
| `banco-horas_…` | `Funcionário;Cargo;Saldo (hh:mm);Saldo do mês (hh:mm)` |
| `vendas-garcom_…` | `Garçom;Funcionário;Quantidade;Vendas (R$);Serviço (R$);Transações` |
| `faturamento_…` | `Data;Forma de pagamento;Valor (R$)` |

O N8N (`exportar-fechamento.json`) gera o CSV de comissão com `n8n/comum/lib/csv.mjs` e o envia por e-mail para `MDG_EMAIL_RELATORIOS`
(nó Send Email; credencial SMTP configurada no N8N). O front gera os mesmos arquivos com `web/src/lib/csv.ts`.

---

## 14. Front-end

### 14.1 Identidade visual — tokens (em `web/src/estilos.css`, bloco `@theme` do Tailwind v4)
Tema **escuro único** (`color-scheme: dark`). Os nomes abaixo são a API: o Tailwind gera `bg-noite`, `text-creme`, `border-borda`,
`rounded-cartao`, `font-display` etc. Nenhuma tela usa cor hexadecimal solta.

| token | valor | uso |
|---|---|---|
| `--color-noite` | `#060A17` | fundo da página |
| `--color-noite-2` | `#0A1022` | barra lateral, rodapés fixos |
| `--color-cartao` | `#121A30` | cartões, modais |
| `--color-cartao-2` | `#18223D` | hover de linha, cabeçalho de tabela |
| `--color-entrada` | `#0C1326` | fundo de inputs |
| `--color-borda` | `#232C47` | bordas sutis |
| `--color-borda-forte` | `#34406A` | foco/hover de inputs |
| `--color-ouro` | `#C9A23D` | acento, botão primário, item ativo |
| `--color-ouro-claro` | `#E8C878` | 2ª linha do título em itálico, destaques |
| `--color-ouro-escuro` | `#9E7C27` | hover/pressionado do botão primário |
| `--color-tinta-ouro` | `#1A1405` | texto sobre o dourado |
| `--color-creme` | `#F4EEDC` | texto principal |
| `--color-lavanda` | `#8D93B8` | texto secundário, rótulos |
| `--color-lavanda-escuro` | `#5E6488` | texto desabilitado, placeholders |
| `--color-sucesso` | `#4FB286` | |
| `--color-alerta` | `#E8873A` | alarmes abertos, atraso |
| `--color-perigo` | `#E5604F` | erros, saldo negativo |
| `--color-info` | `#6FA8DC` | |
| `--font-display` | `'Fraunces Variable', Georgia, serif` | títulos (com itálico) |
| `--font-sans` | `'Manrope Variable', system-ui, sans-serif` | corpo |
| `--font-mono` | `'JetBrains Mono Variable', ui-monospace, monospace` | números tabulares (horários, valores) |
| `--radius-cartao` | `20px` | cartões, modais |
| `--radius-entrada` | `12px` | inputs, botões |
| `--radius-pilula` | `999px` | selos |
| `--shadow-cartao` | `0 1px 0 rgb(255 255 255 / 0.03) inset, 0 24px 48px -24px rgb(0 0 0 / 0.6)` | |

Classes utilitárias (em `estilos.css`, camada `components`): `.sobrancelha` (caixa alta, `letter-spacing: .24em`, 11px, `text-ouro`, peso 700),
`.titulo-display` (Fraunces 400, 32–44px, `text-creme`), `.titulo-italico` (Fraunces itálico, `text-ouro-claro`), `.numero` (mono, `tabular-nums`).
Tela de login: cartão centralizado de 420px; sobrancelha "MEU DIA DE GERENTE"; título em duas linhas ("Bom te ver" / *"de volta."* em itálico dourado-claro);
campos E-mail e Senha; caixa "Manter-me conectado"; botão **Entrar** (dourado, texto `tinta-ouro`); divisor "ou"; botão secundário
**Entrar com Google** (contorno `borda`, ícone G); links "Recuperar senha" e "Criar conta".
Responsivo: 390 px (celular: barra lateral vira menu inferior/gaveta, tabelas viram cartões) e 1440 px (barra lateral fixa 260 px).
Sem rolagem horizontal da página.

### 14.2 Sessão e autenticação (frontend-1)
- `supabase.ts`: cliente com `auth.storage` adaptado: se `localStorage['mdg:lembrar'] === '0'` usa `sessionStorage` ("Manter-me conectado" desmarcado), senão `localStorage`.
- Entrar: `signInWithPassword`. Google: `signInWithOAuth({ provider: 'google', options: { redirectTo: origin + '/' } })`, botão escondido se `VITE_LOGIN_GOOGLE === 'false'`.
- Recuperar: `resetPasswordForEmail(email, { redirectTo: origin + '/redefinir-senha' })`; `/redefinir-senha` chama `updateUser({ password })`.
- Criar conta: `signUp({ email, password, options: { data: { nome } } })` → se houver sessão vai a `/comecar`; senão mostra "confirme seu e-mail".
- `/comecar`: perfil sem empresa → formulário "Nome do estabelecimento" → `criar_minha_empresa`.
- Rotas protegidas: sem sessão → `/entrar`; perfil sem empresa (não master) → `/comecar`; perfil/empresa inativos → tela "Acesso desativado".

### 14.3 Rotas
| rota | página (arquivo → export) | dono | papéis |
|---|---|---|---|
| `/entrar` | `paginas/acesso/PaginaEntrar.tsx` → `PaginaEntrar` | f1 | público |
| `/recuperar-senha` | `paginas/acesso/PaginaRecuperarSenha.tsx` → `PaginaRecuperarSenha` | f1 | público |
| `/redefinir-senha` | `paginas/acesso/PaginaRedefinirSenha.tsx` → `PaginaRedefinirSenha` | f1 | sessão de recuperação |
| `/criar-conta` | `paginas/acesso/PaginaCriarConta.tsx` → `PaginaCriarConta` | f1 | público |
| `/comecar` | `paginas/acesso/PaginaComecar.tsx` → `PaginaComecar` | f1 | logado sem empresa |
| `/` | `paginas/painel/PaginaPainel.tsx` → `PaginaPainel` | f1 | L G A M |
| `/funcionarios` | `paginas/funcionarios/PaginaFuncionarios.tsx` → `PaginaFuncionarios` | f2 | L G A M |
| `/funcionarios/novo`, `/funcionarios/:id` | `paginas/funcionarios/PaginaFuncionario.tsx` → `PaginaFuncionario` | f2 | G A M (L só vê) |
| `/funcionarios/jornadas` | `paginas/funcionarios/PaginaJornadas.tsx` → `PaginaJornadas` | f2 | L G A M |
| `/ponto` (`?data=`) | `paginas/ponto/PaginaPontoDia.tsx` → `PaginaPontoDia` | f2 | L G A M |
| `/ponto/funcionario/:id` (`?mes=AAAA-MM`) | `paginas/ponto/PaginaEspelho.tsx` → `PaginaEspelho` | f2 | L G A M |
| `/ponto/alarmes` (`?status=aberto`) | `paginas/ponto/PaginaAlarmes.tsx` → `PaginaAlarmes` | f2 | L G A M |
| `/banco-de-horas` | `paginas/banco-horas/PaginaBancoHoras.tsx` → `PaginaBancoHoras` | f2 | L G A M |
| `/banco-de-horas/:id` | `paginas/banco-horas/PaginaExtratoBancoHoras.tsx` → `PaginaExtratoBancoHoras` | f2 | L G A M |
| `/vendas` (`?de&ate&loja&aba=faturamento|garcons`) | `paginas/vendas/PaginaVendas.tsx` → `PaginaVendas` | f2 | L G A M |
| `/comissoes` | `paginas/comissoes/PaginaComissoes.tsx` → `PaginaComissoes` | f2 | G A M |
| `/comissoes/:id` | `paginas/comissoes/PaginaFechamento.tsx` → `PaginaFechamento` | f2 | G A M |
| `/tarefas` (`?data=`) | `paginas/tarefas/PaginaTarefas.tsx` → `PaginaTarefas` | f2 | L G A M |
| `/tarefas/rotinas` | `paginas/tarefas/PaginaRotinas.tsx` → `PaginaRotinas` | f2 | G A M |
| `/integracoes` | `paginas/integracoes/PaginaIntegracoes.tsx` → `PaginaIntegracoes` | f1 | G A M |
| `/integracoes/:id` | `paginas/integracoes/PaginaIntegracao.tsx` → `PaginaIntegracao` | f1 | G A M (editar: A M) |
| `/configuracoes` | `paginas/configuracoes/PaginaConfiguracoes.tsx` → `PaginaConfiguracoes` | f1 | A M (G vê) |
| `/usuarios` | `paginas/configuracoes/PaginaUsuarios.tsx` → `PaginaUsuarios` | f1 | A M |
| `/master/empresas` | `paginas/master/PaginaEmpresas.tsx` → `PaginaEmpresas` | f1 | M |
| `/master/empresas/:id` | `paginas/master/PaginaEmpresa.tsx` → `PaginaEmpresa` | f1 | M |
| `*` | `paginas/PaginaNaoEncontrada.tsx` → `PaginaNaoEncontrada` | f1 | |
Páginas são *named exports* sem props; `App.tsx` (f1) as importa com `React.lazy` (`lazy(() => import(...).then(m => ({ default: m.PaginaX })))`).
Menu lateral (ordem): Painel · Ponto · Banco de horas · Funcionários · Vendas · Comissões · Tarefas · Integrações · Configurações · Usuários ·
(master) Empresas. Itens escondidos conforme papel. Master tem **seletor de empresa** no topo da casca (`useEmpresaAtual`).

### 14.4 Conteúdo mínimo das telas
- **Painel** (f1): saudação + data do dia de trabalho; indicadores Faturamento hoje / ontem / mês, Serviço ontem; cartão "Alarmes de ponto"
  (5 últimos + link `/ponto/alarmes`); "Presentes agora x de y escalados"; cartão "Tarefas de hoje" (progresso + lista curta, marcar concluída);
  cartão "Sincronização" (por integração: último sucesso relativo, status, botão "Sincronizar agora" para G A M). Fonte: `painel_do_dia`
  + `tarefas_gerar_do_dia` ao abrir.
- **Funcionários** (f2): lista (busca, filtro ativo/inativo, cargo, pontos, vínculos Control iD/Zig como selos); cadastro com abas
  Dados · Vínculos (escolher usuário Control iD de cada equipamento em `controlid_usuarios`, campo nome Zig com sugestões de
  `employee_name` distintos dos últimos 60 dias) · Comissão (pontos, participa, histórico de `funcionario_pontos`) · Jornada
  (histórico `funcionario_jornadas`, nova vigência). Jornadas: CRUD com grade de 7 dias e previsão de minutos (lib pura).
- **Ponto** (f2): dia (todos os funcionários: batidas, trabalhado, saldo, situação, alarmes); espelho mensal por funcionário (linhas por dia,
  batidas clicáveis para desconsiderar/restaurar, "Incluir batida", justificar alarme, abonar dia, exportar CSV, recalcular);
  alarmes (filtros status/tipo/funcionário/período, justificar em lote = várias chamadas).
- **Banco de horas** (f2): resumo por funcionário (saldo, saldo do mês) + extrato com lançamentos (incluir ajuste/compensação/pagamento/saldo inicial).
- **Vendas** (f2): filtro de período e loja; indicadores (faturamento, vendas, serviço, descontos); faturamento por dia (barras CSS) e por
  forma de pagamento; aba garçons (ranking com valor e serviço, ligação com funcionário); exportar CSV.
- **Comissões** (f2): lista de fechamentos (período, status, base, total); novo fechamento (período, loja, proporcional); detalhe com parâmetros
  editáveis no rascunho, tabela de itens (incluir/excluir, pontos), prévia instantânea com `calcularComissao` (lib pura) enquanto edita e
  valores oficiais do banco após salvar; "Fechar" (A M), "Exportar CSV", "Enviar por e-mail" (`sync_solicitar` escopo `exportar_fechamento`).
- **Tarefas** (f2): lista do dia por status/prioridade, criar avulsa, checklist, atribuir a funcionário/usuário; rotinas recorrentes.
- **Integrações** (f1): cartões por integração (tipo, ativa, último sucesso/erro, histórico de `sync_execucoes` dos últimos 20,
  "Sincronizar agora"); criar/editar (A M): nome, ativa, parâmetros do tipo, intervalo, campos de segredo **somente escrita**
  (mostram "configurado ✓" via `integracao_segredos_preenchidos`); lojas Zig (marcar `sincronizar`); usuários Control iD (lista + vínculo,
  reutilizando o mesmo componente de vínculo — dono f2, ver §14.5); botão "Enviar funcionários ao equipamento" (escopo `exportar_funcionarios`).
- **Configurações** (f1): dados da empresa, fuso, virada do dia, % retenção da comissão, alarme de atraso, janela de duplicidade.
- **Usuários** (f1): lista, criar (`admin_criar_usuario`), editar papel/ativo/vínculo com funcionário, redefinir senha, excluir.
- **Master** (f1): empresas (criar com administrador, ativar/desativar, excluir), detalhe com usuários da empresa.

### 14.5 Componentes compartilhados
`web/src/componentes/ui.tsx` (dono **f1**; o esqueleto já traz as assinaturas e uma implementação simples — f1 refina sem mudar props):

| componente | props |
|---|---|
| `Botao` | `ButtonHTMLAttributes` + `variante?: 'primario' \| 'secundario' \| 'fantasma' \| 'perigo'` (padrão primario), `tamanho?: 'p' \| 'm' \| 'g'`, `carregando?: boolean`, `icone?: ReactNode` |
| `Campo` | `rotulo: string`, `htmlFor?: string`, `ajuda?: ReactNode`, `erro?: string \| null`, `obrigatorio?: boolean`, `children` |
| `Entrada` | `InputHTMLAttributes` + `invalido?: boolean` (forwardRef) |
| `Selecao` | `SelectHTMLAttributes` (forwardRef) |
| `AreaTexto` | `TextareaHTMLAttributes` (forwardRef) |
| `Caixa` | `rotulo: ReactNode`, `marcado: boolean`, `aoMudar(v: boolean)`, `desabilitado?` |
| `Interruptor` | `rotulo: ReactNode`, `marcado: boolean`, `aoMudar(v: boolean)`, `desabilitado?` |
| `EntradaMoeda` | `centavos: number \| null`, `aoMudar(c: number \| null)`, `permitirNegativo?`, `id?`, `desabilitado?` |
| `EntradaData` | `valor: string \| null` (`AAAA-MM-DD`), `aoMudar(v: string \| null)`, `min?`, `max?`, `id?` |
| `EntradaHora` | `valor: string \| null` (`HH:MM`), `aoMudar(v: string \| null)`, `id?` |
| `FiltroPeriodo` | `inicio: string`, `fim: string`, `aoMudar(inicio: string, fim: string)`, `atalhos?: boolean` (Hoje, Ontem, 7 dias, Este mês, Mês anterior) |
| `Cartao` | `titulo?: ReactNode`, `sobrancelha?: string`, `acoes?: ReactNode`, `className?`, `semPreenchimento?: boolean`, `children` |
| `CabecalhoPagina` | `sobrancelha?: string`, `titulo: ReactNode`, `subtitulo?: ReactNode`, `acoes?: ReactNode` |
| `Selo` | `tom?: Tom` (`'neutro' \| 'ouro' \| 'sucesso' \| 'alerta' \| 'perigo' \| 'info'`), `children` |
| `Indicador` | `rotulo: string`, `valor: ReactNode`, `detalhe?: ReactNode`, `tom?: Tom` |
| `Tabela<T>` | `colunas: Coluna<T>[]`, `linhas: T[]`, `chave(l: T): string`, `vazio?: ReactNode`, `carregando?: boolean`, `aoClicarLinha?(l: T)`; `Coluna<T> = { id: string; titulo: ReactNode; render(l: T): ReactNode; alinhar?: 'esquerda' \| 'direita' \| 'centro'; ocultarNoCelular?: boolean }` (no celular vira lista de cartões) |
| `Abas<T extends string>` | `abas: { id: T; rotulo: ReactNode; contador?: number }[]`, `ativa: T`, `aoMudar(id: T)` |
| `Modal` | `aberto: boolean`, `aoFechar()`, `titulo: ReactNode`, `rodape?: ReactNode`, `largura?: 'p' \| 'm' \| 'g'`, `children` |
| `Vazio` | `titulo: string`, `descricao?: ReactNode`, `acao?: ReactNode`, `icone?: ReactNode` |
| `Carregando` | `texto?: string` |
| `Esqueleto` | `className?: string` |
| `ErroCarga` | `erro: unknown`, `aoTentar?(): void` |
`web/src/componentes/avisos.tsx` (f1): `ProvedorDeAvisos`, `useAvisos(): { sucesso(m: string): void; erro(e: unknown): void; info(m: string): void; confirmar(o: { titulo: string; mensagem?: ReactNode; textoConfirmar?: string; perigo?: boolean }): Promise<boolean> }`.
Componentes de domínio de f2 em `web/src/componentes/dominio/`: `SeletorFuncionario` (`valor: string | null`, `aoMudar(id: string | null)`,
`permitirTodos?: boolean`, `somenteAtivos?: boolean`), `VinculoControlId` (`integracaoId?: string`, `funcionarioId?: string` — lista/edita
vínculos de `controlid_usuarios`; f1 usa na página de integração), `SeloSituacaoDia`, `SeloAlarme`.

### 14.6 Bibliotecas e tipos
| arquivo | dono | exporta |
|---|---|---|
| `web/src/tipos/banco.ts` | f1 (versão inicial já escrita no esqueleto) | tipos de todas as tabelas, enums, retornos de RPC e o mapa `Rpcs` (nome → `{ args; retorno }`) |
| `web/src/lib/supabase.ts` | f1 | `supabase`, `configuracaoAusente`, `mensagemDeErro(e: unknown): string`, `exigir<T>(r): T`, `chamarRpc<K extends keyof Rpcs>(nome: K, args: Rpcs[K]['args']): Promise<Rpcs[K]['retorno']>` |
| `web/src/lib/sessao.tsx` | f1 | `ProvedorDeSessao`, `useSessao(): { carregando; sessao; perfil: Perfil \| null; empresa: Empresa \| null; sair(): Promise<void> }`, `usePerfil(): Perfil`, `useEmpresaAtual(): { empresaId: string \| null; empresa: Empresa \| null; definirEmpresa(id: string \| null): void }` |
| `web/src/lib/permissoes.ts` | f1 | `podeOperar(p: Papel)`, `podeAdministrar(p: Papel)`, `ehMaster(p: Papel)`, `podeVerComissoes(p: Papel)` |
| `web/src/lib/formato.ts` | f1 (esqueleto já traz) | `formatarCentavos(c, {sinal?})` → `R$ 1.234,56`; `centavosParaTexto(c)` → `1234,56`; `textoParaCentavos(s)`; `formatarMinutos(m, {sinal?})` → `7h30` / `-3h26`; `minutosHHMM(m)` → `-03:26`; `formatarData(iso)` → `dd/mm/aaaa`; `formatarDataCurta(iso)` → `dd/mm`; `diaSemanaCurto(iso)` → `sáb`; `formatarHora(instanteISO, fuso?)` → `HH:MM` (fuso padrão `America/Sao_Paulo`); `formatarDataHora(instanteISO, fuso?)`; `formatarRelativo(instanteISO)` → `há 5 min`; `hojeISO(fuso?, virada?)` (dia de trabalho); `somarDias(iso, n)`; `normalizar(s)` |
| `web/src/lib/csv.ts` | f1 | `gerarCsv(cabecalho: string[], linhas: unknown[][], preambulo?: string[][]): string` (§13), `baixarCsv(nome: string, conteudo: string): void`, `centavosCsv(c)`, `minutosCsv(m)`, `dataCsv(iso)` |
| `web/src/lib/rotulos.ts` | f1 | mapas `Record<Enum, string>` para todos os enums de `banco.ts` (§14.7) |
| `web/src/lib/consultas.ts` | f1 | `chaves` (fábrica de query keys, §14.8) |
| `web/src/lib/ponto.ts` (+`.test.ts`) | f2 | `minutosPrevistos(jd)`, `batidasEsperadas(jd)`, `instantesEsperados(data, jd, fuso, virada)`, `paresTrabalhados(batidas)`, `rotuloBatidaEsperada` (via rotulos) |
| `web/src/lib/comissao.ts` (+`.test.ts`) | f2 | `calcularComissao(e: EntradaComissao): ResultadoComissao` — réplica exata do §9 (o vitest usa os vetores do §9) |
| `web/src/lib/vendas.ts` (+`.test.ts`) | f2 | agregações/ordenações para gráficos e CSV |
| `web/src/consultas/*.ts` | f2 (`funcionarios.ts`, `ponto.ts`, `bancoHoras.ts`, `vendas.ts`, `comissoes.ts`, `tarefas.ts`) / f1 (`painel.ts`, `integracoes.ts`, `usuarios.ts`, `empresas.ts`) | hooks react-query (`useX`) e mutações |

### 14.7 Rótulos (texto exibido)
- papel: master "Master" · administrador "Administrador" · gerente "Gerente" · leitura "Somente leitura"
- tipo de alarme: batida_faltando "Batida faltando" · batidas_impares "Batidas ímpares" · sem_batida_dia_escalado "Sem batidas no dia escalado" · atraso "Atraso"
- batida esperada: entrada "Entrada" · saida_intervalo "Saída p/ intervalo" · volta_intervalo "Volta do intervalo" · saida "Saída"
- status do alarme: aberto "Aberto" · justificado "Justificado" · resolvido "Resolvido"
- situação do dia: completo "Completo" · incompleto "Incompleto" · ausente "Ausente" · folga "Folga" · sem_escala "Sem escala" · abonado "Abonado" · em_andamento "Em andamento"
- origem: controlid_acesso "Control iD (acesso)" · controlid_rep "Control iD (REP)" · manual "Manual"
- abono: folga "Folga" · feriado "Feriado" · ferias "Férias" · atestado "Atestado" · compensacao "Compensação" · outro "Outro"
- lançamento: saldo_inicial "Saldo inicial" · ajuste "Ajuste" · compensacao "Compensação" · pagamento "Pagamento em folha"
- integração: zig "Zig" · controlid_acesso "Control iD — controle de acesso" · controlid_rep "Control iD — relógio de ponto (REP)"
- execução: executando "Executando" · sucesso "Sucesso" · parcial "Parcial" · erro "Erro"; solicitação: pendente "Na fila" · em_andamento "Sincronizando" · concluida "Concluída" · erro "Erro" · cancelada "Cancelada"
- tarefa: pendente "Pendente" · em_andamento "Em andamento" · concluida "Concluída" · cancelada "Cancelada"; prioridade baixa/normal/alta "Baixa/Normal/Alta"
- fechamento: rascunho "Rascunho" · fechado "Fechado"

### 14.8 Query keys (para invalidação entre módulos)
`['painel', empresaId]` · `['funcionarios', empresaId]` · `['funcionario', id]` · `['jornadas', empresaId]` · `['controlid-usuarios', empresaId]` ·
`['ponto-dia', empresaId, data]` · `['espelho', funcionarioId, inicio, fim]` · `['alarmes', empresaId, filtros]` ·
`['banco-horas', empresaId, ate]` · `['extrato', funcionarioId, inicio, fim]` · `['vendas', empresaId, tipo, inicio, fim, loja]` ·
`['comissoes', empresaId]` · `['fechamento', id]` · `['tarefas', empresaId, data]` · `['rotinas', empresaId]` ·
`['integracoes', empresaId]` · `['sync', empresaId]` · `['usuarios', empresaId]` · `['empresas']`.
Toda mutação de ponto invalida `painel`, `ponto-dia`, `espelho`, `alarmes`, `banco-horas`; de tarefas invalida `painel` e `tarefas`.

---

## 15. Ambiente local, demonstração e testes

### 15.1 Testes de banco (`npm run test:banco`)
- `supabase/testes/preparar-postgres.sh` (b1): cria/sobe um cluster Postgres 16 descartável (`/usr/lib/postgresql/16/bin`), só socket local,
  usuário de SO dedicado; idempotente; imprime o diretório do socket.
- `supabase/testes/00_ambiente_supabase.sql` (b1): imita o Supabase — papéis `anon`, `authenticated`, `service_role` (bypassrls),
  `authenticator`; schemas `auth` (tabelas `users` e `identities` com as colunas do GoTrue, `auth.uid()`, `auth.role()`, `auth.jwt()`
  lendo `request.jwt.claims`/`request.jwt.claim.sub`) e `extensions` (pgcrypto); privilégios padrão do Supabase em `public`
  (ALL para anon/authenticated/service_role em tabelas, funções e sequências novas). Também cria o schema `teste` com
  `teste.ok(descricao text, condicao boolean)` (raise notice `ok` ou exceção `FALHOU`) e `teste.como(email text)` (veste o usuário:
  `set local role authenticated` + claims; `null` = anon) e `teste.como_servico()` (`set local role service_role`).
- `supabase/testes/executar.sh` (b1): recria o banco, aplica `00_ambiente`, migrações, `seed/*.sql`, **migrações de novo**, e roda `NN_*.sql`
  (NN ≥ 10) em ordem; para no primeiro erro; termina com `tudo passou`.
- Cada arquivo de teste roda dentro de `begin; … rollback;` e não depende de outro. Prefixos: b1 = `10_`–`19_` e `90_`; b2 = `20_`–`69_`.
  Arquivos: b1 `10_base_rls.sql`, `12_usuarios.sql`, `14_cadastros.sql`, `16_integracoes_sync.sql`, `18_tarefas.sql`, `90_auditoria.sql`;
  b2 `20_ponto_apuracao.sql`, `22_ponto_alarmes.sql`, `24_ponto_ajustes.sql`, `30_banco_horas.sql`, `40_zig.sql`, `50_comissoes.sql`,
  `60_ingestao.sql`, `65_painel.sql`.
- Obrigatórios: isolamento entre empresas em **toda** tabela (L/G/A da empresa A não vê/escreve nada da B); `anon` sem acesso;
  `integracoes_segredos` invisível a authenticated; `[servico]` negadas a authenticated; idempotência das ingestões (rodar 2× = mesmo
  resultado); vetores do §7.6 e do §9.

### 15.2 Ambiente local completo (b1) — `ferramentas/local/`
`subir.sh`: Postgres (via `preparar-postgres.sh`) + migrações + seed + PostgREST (binário `postgrest` no PATH; se ausente, explica como
instalar) + `portao.mjs` (Node, porta 54321) que imita o necessário do Supabase: `/auth/v1/token` (password e refresh_token, conferindo bcrypt
em `auth.users.encrypted_password`), `/auth/v1/user`, `/auth/v1/logout`, `/auth/v1/signup`, `/auth/v1/recover` (só registra) e repassa
`/rest/v1/*` ao PostgREST. JWT HS256 com segredo local. Grava `.env.local` com `VITE_SUPABASE_URL=http://127.0.0.1:54321`, a anon key e
`VITE_LOGIN_GOOGLE=false`; imprime também a **service_role key** (para o N8N local). README em `ferramentas/local/README.md`.

### 15.3 Carga de demonstração (senha de todos: `gerente123`)
`supabase/seed/10_demo_base.sql` (b1) e `supabase/seed/20_demo_operacao.sql` (b2). Idempotentes (`on conflict do nothing`). Ids fixos:

| objeto | id |
|---|---|
| empresa A "Bar Bossa Nova" (fuso SP, virada 05:00) | `a0000000-0000-4000-8000-00000000000a` |
| empresa B "Cantina Roma" | `b0000000-0000-4000-8000-00000000000b` |
| integração Zig A (`rede-mock`, token `token-mock`, url mock) | `a0000000-0000-4000-8000-000000000101` |
| integração Control iD acesso A (`http://127.0.0.1:54341`) | `a0000000-0000-4000-8000-000000000102` |
| integração Control iD REP A (`http://127.0.0.1:54342`) | `a0000000-0000-4000-8000-000000000103` |
| jornada A "Salão noite" — ter a dom (dow 0,2,3,4,5,6): 17:00/21:00/21:30/01:00 (450 min) | `a0000000-0000-4000-8000-000000000201` |
| jornada A "Cozinha" — seg a sáb (1–6): 10:00/14:00/15:00/18:00 (420 min) | `a0000000-0000-4000-8000-000000000202` |
| funcionários A: Ana Souza (Garçom, 10 pts, matrícula 1, CPF 52998224725) | `…000000000301` |
| Bruno Lima (Garçom, 10, mat. 2, CPF 11144477735) | `…000000000302` |
| Carla Dias (Cumim, 6, mat. 3, CPF 39053344705) | `…000000000303` |
| Davi Rocha (Bartender, 8, mat. 4, CPF 15350946056) | `…000000000304` |
| Eva Martins (Cozinha, 4, mat. 5, CPF 71428793860) — jornada Cozinha; demais Salão noite | `…000000000305` |
| funcionário B: Paolo Bianchi | `b0000000-0000-4000-8000-000000000301` |
(`…` = `a0000000-0000-4000-8000-`.) `zig_employee_name` = nome completo. Usuários: `master@meudiadegerente.app` (master),
`admin@barbossanova.com.br` (administrador A), `gerente@barbossanova.com.br` (gerente A), `leitura@barbossanova.com.br` (leitura A,
`funcionario_id` = Ana), `admin@cantinaroma.com.br` (administrador B). Rotinas de tarefa A: "Abrir caixa" (diária, 16:30, checklist 3 itens),
"Conferir estoque do bar" (semanal ter/sex). A carga b2 gera, **relativa ao dia de trabalho atual**: batidas dos últimos 14 dias (com uma volta
de intervalo faltando, um dia ímpar e uma ausência), dados Zig dos últimos 30 dias (faturamento, itens, Tips) e um fechamento de comissão
`fechado` do mês anterior + um `rascunho` do mês corrente.

### 15.4 E2E (Playwright)
`playwright.config.ts` + `e2e/apoio/` + `e2e/acesso.spec.ts`, `e2e/casca.spec.ts` (f1); `e2e/operacao.spec.ts` (f2). Projetos `desktop`
(1440×900) e `celular` (390×844). Rodam contra o ambiente local (§15.2). Falham com erro no console do navegador.

---

## 16. Ordem de integração e critérios de pronto
1. b1 entrega `…0100`–`…0130` + `…0900` + testes base → b2 aplica `…0200`–`…0240` em cima (o `executar.sh` roda tudo).
2. f1 entrega cedo `ui.tsx`, `avisos.tsx`, `supabase.ts`, `sessao.tsx`, `formato.ts`, `csv.ts`, `rotulos.ts`, `consultas.ts`, `App.tsx` (rotas lazy).
   f2 trabalha contra as assinaturas do §14.5–14.6 (o esqueleto já compila com elas).
3. n8n-1 e n8n-2 testam contra os mocks (§12.6) e o ambiente local (§15.2), usando a service_role impressa pelo `subir.sh`.
4. Pronto = `npm run typecheck && npm test && npm run build && npm run test:banco && npm run n8n:verificar` verdes; `npm run sql:instalar`
   regerado por último (b1).
