# Adendo ao contrato — Ocorrências disciplinares, Extras (freelas, dias trabalhados, rateio diário, gastos) e Reservas (Tagme)

> **Versão 2** — seção E reescrita (extras = freelas/diaristas; comissão com rateio diário). Seções O e R sem mudança.

Dono: **backend** (banco). Implementam contra este adendo: **frontend** (`web/`) e **N8N** (`n8n/`).
Complementa `docs/CONTRATO.md`; onde houver conflito, **este adendo vale**. Convenções de sempre (§2): etiquetas no
`comment on` (§2.2), RLS em tudo, RPC `security definer` com `search_path`, `agora()`, dinheiro em centavos `bigint`,
erros `raise exception '<texto exato>' using errcode` (42501 permissão, 22023 valor, P0002 não encontrado).
Papéis: **L** leitura, **G** gerente, **A** administrador, **M** master. "G A M" = `pode_operar(empresa)`.

Migrações:
| arquivo | conteúdo |
|---|---|
| `…0120_integracoes_sync.sql` (ajuste) | tipo `tagme` (check, parâmetros, segredos), escopo `reservas`, `sync_execucoes.tipo` `tagme_importar` |
| `…0200_ponto.sql` (ajuste) | abono `suspensao`, situação `suspenso`, coluna `ponto_abonos.ocorrencia_id` |
| `…0220_comissoes.sql` (ajuste) | `modo_rateio`, rateio diário (§E.3), tabelas de detalhe, `comissao_detalhe`; remove `comissao_pontos_extras` e `pontos_extras` |
| `…0240_painel.sql` (ajuste) | blocos `reservas` e `ocorrencias` no `painel_do_dia` |
| `…0250_ocorrencias.sql` (nova) | ocorrências, anexos, bucket `funcionarios-documentos`, RPCs |
| `…0260_extras.sql` (nova) | cadastro `extras`, `diarias` (extra ou funcionário), valor padrão de diária, `gastos_periodo`, RPCs (§E) |
| `…0270_reservas.sql` (nova) | `reservas`, RPCs, importação CSV, `ingestao_reservas` |

Testes: `supabase/testes/70_ocorrencias.sql`, `72_extras.sql`, `74_reservas.sql`. Carga demo: `supabase/seed/30_demo_extras.sql`.

---

## O. Ocorrências disciplinares (advertência / suspensão)

### O.1 DDL
```sql
-- ============================================== funcionario_ocorrencias  [api:leitura]  (select: G A M; L NÃO vê)
create table if not exists public.funcionario_ocorrencias (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references public.empresas (id) on delete cascade,     -- gatilho: do funcionário
  funcionario_id    uuid not null references public.funcionarios (id) on delete cascade,
  tipo              text not null check (tipo in ('advertencia', 'suspensao')),
  data              date not null,                         -- data da ocorrência (do fato / da aplicação)
  motivo            text not null check (btrim(motivo) <> ''),
  descricao         text,
  dias_suspensao    int check (dias_suspensao between 1 and 30),
  suspensao_inicio  date,
  suspensao_fim     date,                                  -- = suspensao_inicio + dias_suspensao − 1 (dias corridos)
  criado_por        uuid references public.perfis (id) on delete set null,
  criado_por_nome   text not null,                         -- 'Sistema' sem JWT
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  constraint funcionario_ocorrencias_suspensao check (
    (tipo = 'advertencia' and dias_suspensao is null and suspensao_inicio is null and suspensao_fim is null)
    or (tipo = 'suspensao' and dias_suspensao is not null and suspensao_inicio is not null
        and suspensao_fim = suspensao_inicio + dias_suspensao - 1))
);
-- índices: (empresa_id, data desc), (funcionario_id, data desc), (criado_por)

-- ===================================== funcionario_ocorrencia_anexos  [api:leitura]  (select: G A M)
create table if not exists public.funcionario_ocorrencia_anexos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,      -- gatilho: da ocorrência
  ocorrencia_id   uuid not null references public.funcionario_ocorrencias (id) on delete cascade,
  bucket          text not null default 'funcionarios-documentos',
  caminho         text not null unique,     -- '<empresa_id>/ocorrencias/<ocorrencia_id>/<arquivo>'
  nome_arquivo    text,                     -- nome original exibido (opcional)
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now()
);

-- em ponto_abonos (…0200):  ocorrencia_id uuid references funcionario_ocorrencias(id) on delete cascade  (+ índice)
--   tipo ganha 'suspensao'; ponto_dias.situacao ganha 'suspenso'.
```

### O.2 Storage — bucket privado `funcionarios-documentos`
- `public = false`, `file_size_limit = 5242880` (5 MB), `allowed_mime_types = {image/jpeg, image/png, image/webp, application/pdf}`.
- Caminho: `<empresa_id>/ocorrencias/<ocorrencia_id>/<arquivo>` com extensão `jpg|jpeg|png|webp|pdf` (sem outra `/`).
  Sugestão do front: `<arquivo>` = `<uuid ou timestamp>.<ext>` (evita colisão; o nome original vai em `nome_arquivo`).
- Políticas em `storage.objects` (`mdg_docs_ler/inserir/alterar/excluir`): `bucket_id = 'funcionarios-documentos'` e
  (`eh_master()` ou `(storage.foldername(name))[1] = empresa_operacao()::text`) — **só G A M**, leitura não lê nem envia.
- Fluxo do front: (1) `storage.from('funcionarios-documentos').upload(caminho, arquivo)`; (2) `ocorrencia_adicionar_anexo`.
  Ver: `createSignedUrl(caminho, 300)`. Remover: (1) RPC `ocorrencia_remover_anexo` (devolve o caminho); (2) `storage.remove([caminho])`.
  Excluir ocorrência: RPC devolve os caminhos dos anexos → `storage.remove(caminhos)`. (O banco não apaga objetos do Storage.)

### O.3 Regras
- Data: `p_data ≤ dia de trabalho atual` (`Data no futuro`).
- Suspensão: `p_dias_suspensao` obrigatório (1..30; senão `Dias de suspensão inválidos (1 a 30)`), `p_suspensao_inicio`
  padrão = `p_data`; tem de estar em `[p_data, p_data + 60]` (`Início da suspensão inválido`). `suspensao_fim` é calculado.
  Advertência: os campos de suspensão são ignorados (gravados null).
- **Integração com o ponto** (§7): ao criar/editar/excluir uma suspensão o banco mantém **um abono por dia** em `ponto_abonos`
  (`tipo = 'suspensao'`, `funcionario_id`, `ocorrencia_id`, `motivo = 'Suspensão: <motivo>'`) para cada dia de
  `[suspensao_inicio, suspensao_fim]` e reapura esses dias (e os antigos, ao editar). Consequências (sem regra nova no cálculo):
  dia suspenso tem `previsto = 0`, `esperadas = 0` → **nenhum alarme** (nem `sem_batida_dia_escalado`) e saldo 0 (não fica negativo);
  `situacao = 'suspenso'` (no lugar de `abonado`) quando `abono_tipo = 'suspensao'` e o dia está encerrado; `abono_tipo = 'suspensao'`.
  Sem batidas → não conta em `dias_trabalhados` da comissão.
  - Conflito: já existe abono **do funcionário** (não da empresa) num desses dias que não seja desta ocorrência →
    `Já existe abono para o funcionário em DD/MM/AAAA` (22023). (Feriado da empresa toda não conflita: o abono do funcionário prevalece.)
  - `ponto_abonar` com `p_tipo = 'suspensao'` → `Tipo de abono inválido`; `ponto_abonar` de um funcionário em dia com suspensão, ou
    `ponto_remover_abono` de abono gerado por ocorrência → `Dia com suspensão: altere pela ocorrência` (22023).
  - Front de ponto (`web/src/lib/ponto.ts`, prévia/fuzz): mesma regra da situação — encerrado e abono `suspensao` → `suspenso`;
    rótulo **"Suspenso"**; rótulo do abono `suspensao` = **"Suspensão"**. `banco_horas_extrato` usa "Suspenso (suspensao)".
- Anexos: máx. 10 por ocorrência (`Limite de 10 anexos por ocorrência`); caminho fora do padrão → `Anexo inválido`; objeto
  inexistente no Storage → `Anexo não encontrado no armazenamento` (P0002); caminho repetido → `Anexo já registrado` (23505).

### O.4 RPCs (todas `[api]`, G A M; leitura recebe `Sem permissão`)
| assinatura | retorno / regra |
|---|---|
| `ocorrencia_criar(p_funcionario uuid, p_tipo text, p_data date, p_motivo text, p_descricao text default null, p_dias_suspensao int default null, p_suspensao_inicio date default null) returns uuid` | id. `Tipo de ocorrência inválido`, `Informe o motivo`, `Informe a data`, `Funcionário não encontrado` |
| `ocorrencia_atualizar(p_ocorrencia uuid, p_tipo text, p_data date, p_motivo text, p_descricao text, p_dias_suspensao int default null, p_suspensao_inicio date default null) returns void` | substitui tudo (mesmas validações); ressincroniza abonos/reapura. `Ocorrência não encontrada` |
| `ocorrencia_excluir(p_ocorrencia uuid) returns text[]` | caminhos dos anexos (para `storage.remove`); remove abonos (cascata) e reapura |
| `ocorrencia_adicionar_anexo(p_ocorrencia uuid, p_caminho text, p_nome_arquivo text default null) returns uuid` | id do anexo |
| `ocorrencia_remover_anexo(p_anexo uuid) returns text` | caminho removido. `Anexo não encontrado` |
| `ocorrencias_listar(p_funcionario uuid) returns jsonb` | lista (abaixo), ordem `data desc, criado_em desc` |
| `ocorrencias_contagem(p_funcionario uuid default null, p_empresa uuid default null) returns table(funcionario_id uuid, advertencias int, suspensoes int, dias_suspensao int, ultima_data date)` | só funcionários com ≥ 1 ocorrência; `p_funcionario` informado → 0 ou 1 linha (empresa derivada dele) |
| `ocorrencias_resumo(p_dias int default 30, p_empresa uuid default null) returns jsonb` | resumo (abaixo); `p_dias` 1..366 |

`ocorrencias_listar`:
```json
[ { "id": "uuid", "funcionario_id": "uuid", "tipo": "suspensao", "data": "2026-11-10", "motivo": "Falta sem aviso",
    "descricao": null, "dias_suspensao": 2, "suspensao_inicio": "2026-11-11", "suspensao_fim": "2026-11-12",
    "criado_por_nome": "Gerente Bossa", "criado_em": "ISO", "atualizado_em": "ISO",
    "anexos": [ { "id": "uuid", "caminho": "<empresa>/ocorrencias/<id>/a.jpg", "nome_arquivo": "assinada.jpg", "criado_em": "ISO" } ] } ]
```
`ocorrencias_resumo` (também é o bloco `ocorrencias` do painel, com `p_dias = 30`):
```json
{ "desde": "2026-10-14", "ate": "2026-11-12", "advertencias": 2, "suspensoes": 1, "suspensos_hoje": 1,
  "recentes": [ { "id": "uuid", "funcionario_id": "uuid", "funcionario_nome": "Davi Rocha", "tipo": "advertencia",
                  "data": "2026-11-10", "motivo": "Atraso recorrente", "dias_suspensao": null,
                  "suspensao_inicio": null, "suspensao_fim": null } ] }
```
`desde = hoje − p_dias + 1`, `ate = hoje` (dia de trabalho atual); contagens por `data` em `[desde, ate]`; `suspensos_hoje` =
funcionários com suspensão cobrindo hoje (`hoje ∈ [suspensao_inicio, suspensao_fim]`); `recentes` = até 10, `data desc, criado_em desc`.

---

## E. Extras (v2 — freelas/diaristas)

> **v2 (correção do cliente).** O conceito da v1 ("pontos extras de comissão" lançados para funcionários) estava errado e foi
> **removido**. **Extra = freela/diarista** que trabalha em dias avulsos: tem cadastro próprio (com pontuação e diária padrão),
> cada dia trabalhado é lançado, e os pontos do dia entram na comissão **daquele dia** (rateio diário, E.3).
> Removidos do banco (DROPs idempotentes — quem já rodou a v1 no Supabase só roda a instalação de novo):
> tabela `comissao_pontos_extras`, coluna `comissao_itens.pontos_extras`, RPCs `comissao_extra_lancar`, `comissao_extra_excluir`,
> `comissao_extras_listar`, e as assinaturas antigas de `diaria_lancar`, `diaria_atualizar`, `diarias_listar` e
> `comissao_criar_fechamento`/`comissao_atualizar_fechamento` (ganharam parâmetro novo). O "nome avulso" da diária acabou:
> **todo extra é cadastrado** (o front cria o cadastro na hora, `extra_criar`, e lança em seguida).
> Atualização por cima da v1: cada diária avulsa vira um extra cadastrado (um por empresa + nome sem diferença de maiúsculas;
> pontuação 0, diária padrão = valor da diária mais recente) e o lançamento passa a ser `tipo = 'extra'` com `pontos = 0`.
> Fechamentos existentes ficam `modo_rateio = 'periodo'` (os fechados não são recalculados; os valores ficam como estavam).

### E.1 Cadastro de extras

```sql
-- ============================================================== extras  [api:leitura]  (select: G A M; L NÃO vê)
create table if not exists public.extras (
  id                     uuid primary key default gen_random_uuid(),
  empresa_id             uuid not null references public.empresas (id) on delete cascade,
  nome                   text not null check (btrim(nome) <> ''),
  funcao                 text,                                    -- ex.: 'Garçom', 'Cozinha'
  telefone               text,                                    -- opcional (dado pessoal)
  documento              text,                                    -- opcional, livre (CPF/RG; dado pessoal)
  pontos_padrao          numeric(8,2) not null default 0 check (pontos_padrao between 0 and 9999.99),
  valor_diaria_centavos  bigint check (valor_diaria_centavos between 0 and 100000000),   -- null = sem padrão
  ativo                  boolean not null default true,
  observacoes            text,
  criado_por             uuid references public.perfis (id) on delete set null,
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now()
);
-- índices: (empresa_id, lower(nome)), (criado_por)
```
Regras: textos com `btrim`, vazio → `null` (nome vazio → `Informe o nome`); pontos com no máximo 2 casas em 0..9999,99
(`Pontos inválidos`); valor em 0..100000000 (`Valor inválido`). Nome não é único (dois freelas podem ter o mesmo nome).
Excluir só sem dias lançados (`Extra com dias lançados: desative em vez de excluir`); senão desative (`ativo = false`).
Extra inativo não recebe lançamento novo (`Extra inativo`), mas os lançamentos antigos continuam valendo.

RPCs (`[api]`, G A M; leitura recebe `Sem permissão`):
| assinatura | retorno / regra |
|---|---|
| `extra_criar(p_nome text, p_funcao text default null, p_pontos_padrao numeric default 0, p_valor_diaria_centavos bigint default null, p_telefone text default null, p_documento text default null, p_observacoes text default null, p_empresa uuid default null) returns uuid` | id; `p_pontos_padrao null` = 0 |
| `extra_atualizar(p_extra uuid, p_nome text, p_funcao text, p_pontos_padrao numeric, p_valor_diaria_centavos bigint, p_telefone text, p_documento text, p_ativo boolean, p_observacoes text) returns void` | **substitui tudo** (`p_pontos_padrao null` = 0, `p_valor null` = sem padrão, `p_ativo null` = true); `Extra não encontrado` (P0002). Não altera dias já lançados |
| `extra_excluir(p_extra uuid) returns void` | `Extra não encontrado`, `Extra com dias lançados: desative em vez de excluir` (22023) |
| `extras_listar(p_incluir_inativos boolean default false, p_empresa uuid default null) returns table(id uuid, nome text, funcao text, telefone text, documento text, pontos_padrao numeric, valor_diaria_centavos bigint, ativo boolean, observacoes text, dias_lancados int, ultimo_dia date, criado_em timestamptz)` | ordem `lower(nome), id`; `dias_lancados`/`ultimo_dia` = todos os lançamentos do extra |

### E.2 Dias trabalhados (tabela `diarias`)

Um lançamento é **de um extra** (tem pontos, que entram na comissão do dia) **ou de um funcionário** (só custo, sem pontos).

```sql
-- ===================================================== diarias  [api:leitura]  (select: G A M; L NÃO vê)
create table if not exists public.diarias (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,   -- gatilho: do extra/funcionário
  tipo             text not null default 'funcionario' check (tipo in ('extra', 'funcionario')),
  extra_id         uuid references public.extras (id),                               -- sem cascade: extra com dias não é excluído
  funcionario_id   uuid references public.funcionarios (id) on delete set null,
  pessoa_nome      text not null check (btrim(pessoa_nome) <> ''),   -- snapshot do nome no lançamento
  data             date not null,
  funcao           text,                                             -- padrão: função do extra / cargo do funcionário
  pontos           numeric(8,2) check (pontos between 0 and 9999.99),-- só extra (padrão: pontos_padrao); null em funcionário
  valor_centavos   bigint not null check (valor_centavos between 0 and 100000000),
  observacao       text,
  pago             boolean not null default false,
  pago_em          date,                                             -- null se não pago
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  constraint diarias_pagamento check (pago or pago_em is null),
  constraint diarias_participante check (
    (tipo = 'extra' and extra_id is not null and funcionario_id is null and pontos is not null)
    or (tipo = 'funcionario' and extra_id is null and pontos is null))
);
create unique index if not exists diarias_extra_dia_uidx on public.diarias (extra_id, data) where extra_id is not null;
-- funcionario_valores_diaria (valor padrão da diária do FUNCIONÁRIO): sem mudança desde a v1.
```

Regras:
- Exatamente um de `p_extra` / `p_funcionario` (`Informe o extra ou o funcionário`, 22023). Mesma empresa (`Extra de outra empresa` /
  `Funcionário de outra empresa`; de empresa que o usuário não opera → `Sem permissão`).
- **Extra**: precisa estar ativo (`Extra inativo`); `pontos` padrão = `pontos_padrao` (2 casas, 0..9999,99, `Pontos inválidos`);
  `valor` padrão = `valor_diaria_centavos` do cadastro; `funcao` padrão = função do cadastro. **Um lançamento por extra por dia**
  (`Extra já tem dia lançado em DD/MM/AAAA`, 23505).
- **Funcionário**: `p_pontos` deve ser `null` (`Diária de funcionário não tem pontos`); `valor` padrão = `funcionario_valores_diaria`;
  `funcao` padrão = cargo. Pode haver mais de uma no mesmo dia. Não afeta comissão.
- Sem valor e sem padrão → `Informe o valor da diária`; `Valor inválido` fora de 0..100000000; data em `[hoje − 366, hoje + 62]`
  (`Data fora do limite`); `p_pago = true` e `p_pago_em null` → `pago_em` = dia de trabalho atual; `p_pago = false` → `pago_em null`.
- **Trava de comissão** (só `tipo = 'extra'`): se a data (antiga ou nova) estiver dentro de um fechamento **fechado** da empresa
  (qualquer loja/modo), é recusado com `Período de comissão já fechado` (22023): lançar, excluir, mudar a `data` ou os `pontos`.
  **Pagamento, valor, função e observação continuam editáveis** (não afetam a comissão). Diária de funcionário nunca trava.
- Rascunhos **não** são recalculados sozinhos: o front chama `comissao_recalcular` (ou avisa "recalcule para incluir os extras").

RPCs (`[api]`, G A M):
| assinatura | retorno / regra |
|---|---|
| `diaria_lancar(p_data date, p_extra uuid default null, p_funcionario uuid default null, p_pontos numeric default null, p_valor_centavos bigint default null, p_funcao text default null, p_observacao text default null, p_pago boolean default false, p_pago_em date default null) returns uuid` | id (empresa vem do extra/funcionário) |
| `diaria_atualizar(p_diaria uuid, p_data date, p_pontos numeric, p_valor_centavos bigint, p_funcao text, p_observacao text, p_pago boolean, p_pago_em date) returns void` | a pessoa não muda (exclua e lance de novo). `null` **mantém** em `p_data`, `p_pontos`, `p_valor_centavos` e `p_pago` (com `p_pago null` o `pago_em` também fica); `p_funcao`/`p_observacao` substituem (vazio → padrão / `null`). `Diária não encontrada` |
| `diaria_marcar_paga(p_diaria uuid, p_pago boolean, p_pago_em date default null) returns void` | sem mudança (nunca trava) |
| `diaria_excluir(p_diaria uuid) returns void` | trava de comissão para extra |
| `diarias_listar(p_inicio date, p_fim date, p_tipo text default null, p_extra uuid default null, p_funcionario uuid default null, p_pago boolean default null, p_empresa uuid default null) returns table(id uuid, data date, tipo text, extra_id uuid, funcionario_id uuid, pessoa_nome text, funcao text, pontos numeric, valor_centavos bigint, observacao text, pago boolean, pago_em date, fechado boolean, criado_por_nome text, criado_em timestamptz)` | máx. 366 dias; `p_tipo` em `extra`/`funcionario` (`Tipo inválido`); `pessoa_nome` = nome atual do cadastro (ou o snapshot); `fechado` = tipo extra e data em fechamento fechado; ordem `data desc, pessoa_nome, criado_em, id` |
| `funcionario_definir_valor_diaria(p_funcionario uuid, p_valor_centavos bigint) returns void` · `funcionario_valores_diaria_listar(p_empresa uuid default null) returns table(funcionario_id uuid, valor_diaria_centavos bigint)` | sem mudança desde a v1 |

### E.3 Comissão com rateio diário (substitui o §9 para `modo_rateio = 'diario'`)

#### E.3.1 DDL (ajustes em `…0220_comissoes.sql` e `…0260_extras.sql`)
```sql
-- comissao_fechamentos ganha:
modo_rateio             text not null default 'diario' check (modo_rateio in ('diario', 'periodo')),
                        -- coluna criada com default 'periodo' (fechamentos existentes) e o default trocado para 'diario'
dias_sem_presenca       int  not null default 0,   -- modo diário: dias com base > 0 rateados pelo fallback (sem presença)
dias_sem_participantes  int  not null default 0,   -- modo diário: dias com base > 0 sem ninguém para ratear (fechar é recusado)

-- comissao_itens: participante = funcionário OU extra (snapshot de nome/cargo em funcionario_nome/cargo)
tipo            text not null default 'funcionario' check (tipo in ('funcionario', 'extra')),
extra_id        uuid references public.extras (id) on delete set null,
dias_presentes  int not null default 0,          -- funcionário: dias com batida válida no período; extra: dias lançados
pontos_manual   boolean not null default false,  -- funcionário: pontos fixados no rascunho (senão: vigentes de cada dia)
constraint comissao_itens_participante check ((tipo = 'funcionario' and extra_id is null) or (tipo = 'extra' and funcionario_id is null)),
unique (fechamento_id, extra_id)                 -- além do unique (fechamento_id, funcionario_id) existente
-- REMOVIDA: pontos_extras.  dias_trabalhados continua (= dias_presentes; mantida por compatibilidade).

-- ======================================== comissao_rateio_dias  [api:leitura]  (select: G A M) — um por dia (modo diário)
create table if not exists public.comissao_rateio_dias (
  fechamento_id           uuid not null references public.comissao_fechamentos (id) on delete cascade,
  empresa_id              uuid not null references public.empresas (id) on delete cascade,
  data                    date not null,
  servico_zig_centavos    bigint not null,   -- Tips do dia (loja do fechamento, se houver)
  ajuste_centavos         bigint not null,   -- parte do ajuste manual que coube ao dia (E.3.2 passo 2)
  servico_bruto_centavos  bigint not null,   -- greatest(0, servico + ajuste)
  retencao_centavos       bigint not null,
  base_centavos           bigint not null,
  soma_pontos             numeric(18,2) not null,
  participantes           int not null,
  sem_presenca            boolean not null,  -- base > 0 e ninguém presente → rateado entre os funcionários incluídos
  sem_participantes       boolean not null,  -- base > 0 e ninguém nem no fallback → não rateado
  primary key (fechamento_id, data)
);
-- ================================= comissao_rateio_itens_dia  [api:leitura]  (select: G A M) — participante × dia
create table if not exists public.comissao_rateio_itens_dia (
  item_id         uuid not null references public.comissao_itens (id) on delete cascade,
  fechamento_id   uuid not null references public.comissao_fechamentos (id) on delete cascade,
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  data            date not null,
  pontos          numeric(8,2) not null,     -- pontos usados no dia (> 0)
  valor_centavos  bigint not null,
  fallback        boolean not null,          -- entrou pelo fallback (dia sem presença)
  primary key (item_id, data)
);
-- índices: (fechamento_id, data), (empresa_id, data). As duas tabelas: fechamento 'fechado' = imutável (mesmo gatilho dos itens);
-- no modo 'periodo' ficam vazias. Recalcular o rascunho apaga e regrava as duas.
```

#### E.3.2 Regra (modo `diario`, padrão para fechamentos novos)
Período `[data_inicio, data_fim]` com `D = dias_periodo` dias, loja opcional, `pct = percentual_retencao`, ajuste `A`.
1. **Serviço do dia** `s_d` = Σ `valor_total` dos itens `Tip` com `data_operacao = d` (e loja). `servico_zig = Σ s_d` (igual a hoje).
2. **Ajuste do dia** `a_d` (exato em centavos, maior resto): reparte `|A|` entre os dias com peso `max(s_d, 0)` (se a soma dos pesos for 0,
   peso 1 para todos os dias): `piso_d = div(|A| × w_d, Σ w)`, sobra `|A| − Σ piso_d` → +1 para os dias em ordem de `mod(|A| × w_d, Σ w)` desc,
   `data` asc; `a_d = sinal(A) × parte_d`. Assim `Σ a_d = A` sempre.
3. `bruto_d = greatest(0, s_d + a_d)`; `retencao_d = round(bruto_d × pct / 100)` (meio para longe do zero); `base_d = bruto_d − retencao_d`.
   Totais do fechamento: `servico_bruto = Σ bruto_d` (= `greatest(0, servico_zig + A)` quando nenhum dia tem serviço negativo,
   porque a parte do ajuste nunca passa do serviço do dia quando `A ≥ −servico_zig`), **`retencao = Σ retencao_d`** (pode diferir em centavos de `round(bruto × pct/100)` do
   modo período — é a regra), `base_distribuivel = Σ base_d`.
4. **Participantes do dia** (só itens `incluido = true`):
   - funcionário com `ponto_dias.batidas_validas > 0` no dia `d`, com `pontos_d` = `item.pontos` se `pontos_manual`, senão
     `pontos_vigentes(funcionário, d)`; suspensão/abono/falta = sem presença;
   - extra com lançamento (`diarias.tipo = 'extra'`) no dia `d`, com `pontos_d` = `diarias.pontos` do lançamento;
   - só entra quem tem `pontos_d > 0`.
5. **Fallback** (dia com `base_d > 0` e **ninguém** presente — ex.: ponto ainda não integrado): participam **todos os funcionários
   incluídos** com `pontos_d > 0` (`item.pontos` se `pontos_manual` ou se o funcionário foi excluído — snapshot sem id —, senão os
   vigentes do dia); o dia fica `sem_presenca = true` e o item `fallback = true` (o front avisa "dia sem presença registrada").
   Extras nunca entram por fallback. Se nem assim houver alguém: `sem_participantes = true`, nada é rateado no dia e
   **fechar é recusado** com `Há dias com serviço sem participantes para ratear` (22023).
6. **Rateio do dia** (maior resto exato, igual ao §9 passo 9): `piso_i = div(base_d × p_i, S_d)`, resto `= mod(base_d × p_i, S_d)`,
   com `S_d = Σ p_i`; a sobra `base_d − Σ piso_i` dá +1 por ordem: resto desc, `pontos_d` desc, nome `collate "C"` asc,
   tipo (`funcionario` antes de `extra`), id do participante (`funcionario_id`/`extra_id`) asc nulos por último, `item.id`.
   **Garantia**: em todo dia com participantes, `Σ valores do dia = base_d`; logo `Σ valor_centavos dos itens = base_distribuivel`
   sempre que `dias_sem_participantes = 0` (condição para fechar). Dias com `base_d = 0` também gravam os presentes (valor 0).
7. **Item**: `valor_centavos = Σ` dos dias; `pontos_efetivos = Σ pontos_d` dos dias em que entrou (inclusive fallback);
   `dias_presentes` (= `dias_trabalhados`) = funcionário: dias com batida válida no período; extra: dias lançados no período.
   `pontos`: funcionário = `pontos_vigentes(funcionário, data_fim)` (ou o manual); **extra = média dos pontos dos lançamentos do
   período, 2 casas** (`round(avg, 2)`; sem lançamento: `pontos_padrao`) — só para exibir.
   Fechamento: `soma_pontos_efetivos = Σ soma_pontos dos dias`, `valor_ponto_centavos = round(base / soma, 6)` (média, só exibição;
   `null` se soma 0), `dias_sem_presenca`, `dias_sem_participantes`.
8. **Extras no rascunho**: a cada cálculo, todo extra com lançamento no período que ainda não tem item **entra** (`incluido = true`,
   snapshot nome/função atualizados a cada cálculo enquanto rascunho); item de extra sem nenhum lançamento no período é apagado.
   Tirar um extra = `comissao_definir_extra(…, false)` → `incluido = false` (não volta sozinho).
9. `proporcional_dias` é ignorado no modo diário (a presença já é dia a dia).

**Modo `periodo`** (opção para quem não tem ponto integrado; fechamentos antigos): exatamente o §9 (passos 1–9, com `proporcional_dias`
opcional, `pontos` do item), mais os extras: `pontos_efetivos(extra) = incluido ? round(Σ pontos dos lançamentos do período / dias_periodo, 6) : 0`
(o extra vale a fração de "um período inteiro" que trabalhou, com ou sem `proporcional_dias`). Desempate como no passo 6.
As tabelas de detalhe ficam vazias.

#### E.3.3 Vetores (banco `50_comissoes.sql` e vitest)
**V1 — diário, 3 dias, extra e fallback.** Período 01/09 a 03/09/2026, retenção 20%, ajuste 0. Tips: 01/09 `100000`, 02/09 `50001`, 03/09 `30000`.
Ana Souza 10, Bruno Lima 10, Carla Dias 6 (funcionários); Marcos Freitas = extra (lançado 01/09 com 5 pontos e 02/09 com 7,5).
Presença: 01/09 Ana, Bruno, Carla; 02/09 Ana, Carla; 03/09 ninguém.

| dia | serviço | bruto | retenção | base | participantes (pontos) | soma | valores |
|---|---|---|---|---|---|---|---|
| 01/09 | 100000 | 100000 | 20000 | 80000 | Ana 10, Bruno 10, Carla 6, Marcos 5 | 31 | Ana **25807**, Bruno 25806, Carla 15484, Marcos 12903 |
| 02/09 | 50001 | 50001 | 10000 | 40001 | Ana 10, Carla 6, Marcos 7,5 | 23,5 | Ana 17022, Carla 10213, Marcos 12766 |
| 03/09 | 30000 | 30000 | 6000 | 24000 | **fallback**: Ana 10, Bruno 10, Carla 6 (`sem_presenca`) | 26 | Ana 9231, Bruno 9231, Carla 5538 |

01/09: pisos 25806, 25806, 15483, 12903 (Σ 79998), sobra 2 → Carla (fração 0,871) e Ana (0,452; empata com Bruno, ganha pelo nome).
Totais: **Ana 52060, Bruno 35037, Carla 31235, Marcos 25669** = 144001 = base (80000 + 40001 + 24000); retenção 36000;
`dias_sem_presenca = 1`; Marcos `pontos` 6,25 (média), `dias_presentes` 2, `pontos_efetivos` 12,5; Ana `dias_presentes` 2, `pontos_efetivos` 30.

**V2 — mesmo cenário, ajuste +1000** (peso = serviço do dia, Σ 180001): exatos 555,552 / 277,782 / 166,666 → pisos 555, 277, 166,
sobra 2 → 02/09 e 03/09: **a = 555, 278, 167**. bruto 100555 / 50279 / 30167; retenção 20111 / 10056 / 6033; base 80444 / 40223 / 24134.
Valores: 01/09 Ana 25950, Bruno 25949, Carla 15570, Marcos 12975; 02/09 Ana 17116, Carla 10270, Marcos 12837; 03/09 Ana 9282, Bruno 9282,
Carla 5570. Totais **Ana 52348, Bruno 35231, Carla 31410, Marcos 25812** = 144801; retenção 36200.

**V3 — ajuste −500**: partes de 500 = 277,776 / 138,891 / 83,333 → 277, 138, 83 (+1 para 02/09 e 01/09) → **a = −278, −139, −83**;
bruto 99722 / 49862 / 29917; retenção 19944 / 9972 / 5983; base 79778 / 39890 / 23934; totais **Ana 51915, Bruno 34940, Carla 31149,
Marcos 25598** = 143602.

**V4 — sem serviço, ajuste +100, retenção 0%**: peso igual → **a = 34, 33, 33** (sobra para o 1º dia); valores 01/09 Ana 11, Bruno 11,
Carla 7, Marcos 5; 02/09 Ana 14, Carla 8, Marcos 11; 03/09 (fallback) Ana 13, Bruno 13, Carla 7 → **Ana 38, Bruno 24, Carla 22, Marcos 16** = 100.

**V5 — ajuste ≤ −serviço** (ex.: −180501): todos os dias com bruto 0, base 0, valores 0 (presentes gravados com valor 0).

**V6 — modo período + extra.** Exemplo do §9 (base 796000, não proporcional, Ana 10, Bruno 10, Carla 6, Davi 8, Eva 4) + extra Marcos
com 3 lançamentos de 5 pontos num período de 30 dias → pe = 15/30 = 0,5; soma 38,5; pisos 206753, 206753, 124051, 165402, 82701, 10337
(Σ 795997), sobra 3 → Carla (0,948), Marcos (0,662), Davi (0,597): **Ana 206753, Bruno 206753, Carla 124052, Davi 165403, Eva 82701,
Marcos 10338** (Σ 796000).

#### E.3.4 RPCs de comissão (mudanças; demais do §10.6 sem mudança)
| assinatura | regra |
|---|---|
| `comissao_criar_fechamento(p_data_inicio date, p_data_fim date, p_titulo text default null, p_loja text default null, p_proporcional_dias boolean default false, p_empresa uuid default null, p_modo_rateio text default 'diario') returns uuid` | `Modo de rateio inválido` (22023). Itens: funcionários como hoje + extras com lançamento no período |
| `comissao_atualizar_fechamento(p_fechamento uuid, p_titulo text, p_servico_ajuste_centavos bigint, p_percentual_retencao numeric, p_proporcional_dias boolean, p_observacoes text, p_modo_rateio text default null) returns void` | `p_modo_rateio null` mantém |
| `comissao_definir_item(p_fechamento uuid, p_funcionario uuid, p_pontos numeric, p_incluido boolean default true) returns void` | **`p_pontos null` = automático** (`pontos_manual = false`, pontos vigentes); número = manual (`pontos_manual = true`). O front manda `null` quando o usuário não fixou pontos |
| `comissao_definir_extra(p_fechamento uuid, p_extra uuid, p_incluido boolean) returns void` | inclui/tira o extra; `Extra não encontrado`, `Extra de outra empresa`, `Extra sem dias lançados no período` (22023, ao incluir quem não tem lançamento) |
| `comissao_remover_item(p_fechamento uuid, p_funcionario uuid) returns void` | só funcionário (apaga o item); para extra use `comissao_definir_extra` |
| `comissao_detalhe(p_fechamento uuid) returns jsonb` | **novo**, G A M; formato abaixo |

`comissao_detalhe` — formato exato (o front exibe o rateio e recalcula a prévia com `entrada` + `servico_dias`):
```json
{
  "fechamento": { "...": "todas as colunas de comissao_fechamentos" },
  "servico_dias": [ { "data": "2026-09-01", "servico_zig_centavos": 100000 } ],
  "dias": [ { "data": "2026-09-01", "servico_zig_centavos": 100000, "ajuste_centavos": 0, "servico_bruto_centavos": 100000,
              "retencao_centavos": 20000, "base_centavos": 80000, "soma_pontos": 31.00, "participantes": 4,
              "sem_presenca": false, "sem_participantes": false,
              "rateio": [ { "item_id": "uuid", "pontos": 10.00, "valor_centavos": 25807, "fallback": false } ] } ],
  "itens": [ { "id": "uuid", "tipo": "funcionario", "funcionario_id": "uuid|null", "extra_id": "uuid|null",
               "nome": "Ana Souza", "cargo": "Garçom", "incluido": true, "pontos": 10.00, "pontos_manual": false,
               "dias_presentes": 2, "pontos_efetivos": 30.000000, "valor_centavos": 52060,
               "entrada": [ { "data": "2026-09-01", "presente": true, "pontos": 10.00 } ] } ]
}
```
- `servico_dias`: **um por dia** do período (zeros incluídos), Tips da loja do fechamento — sempre (qualquer modo).
- `dias`: um por dia do período no modo diário (o que está gravado em `comissao_rateio_dias`); `[]` no modo período.
  `rateio` em ordem de nome (`collate "C"`), tipo, id.
- `itens`: ordem nome (`collate "C"`), tipo, id. `entrada` (para a prévia): funcionário com id → **um por dia** do período,
  `presente` = batida válida no dia, `pontos` = vigentes na data (a prévia usa `item.pontos` quando `pontos_manual`);
  extra → um por lançamento do período (`presente = true`, `pontos` do lançamento); snapshot sem id → `[]` (usa `item.pontos`).
- Fechamento de outra empresa / leitura → `Sem permissão`; inexistente → `Fechamento não encontrado`.
- `ingestao_fechamento_exportar` (N8N) passa a devolver também `"dias"` (linhas de `comissao_rateio_dias`, por data) e os itens com as
  colunas novas (`tipo`, `extra_id`, `dias_presentes`, `pontos_manual`); itens por `funcionario_nome`, `tipo`, id.

**Para o front replicar** (`web/src/lib/comissao.ts`): modo período = algoritmo atual (sem `pontosExtras`; extras com
`pe6 = dividirArredondando(Σpontos6, diasPeriodo)`); modo diário = E.3.2 com aritmética inteira (pontos em escala 10², que é
exata para `numeric(8,2)`), usando `servico_dias`, `itens[].entrada`, `incluido`, `pontos_manual`/`pontos`. Vetores V1–V6.

### E.4 CSV de comissão (§13 — front e N8N geram **idêntico**)
Preâmbulo (nesta ordem; `chave;valor`):
`Período;dd/mm/aaaa a dd/mm/aaaa` · `Modo de rateio;Diário` ou `Modo de rateio;Por período` · `Serviço Zig (R$)` · `Ajuste (R$)` ·
`Serviço bruto (R$)` · `Retenção (%)` · `Retenção (R$)` · `Base distribuível (R$)` · `Valor do ponto (R$)` · `Status;Fechado|Rascunho` ·
**só no modo diário**: `Dias sem presença registrada;<dias_sem_presenca>` (inteiro) · linha em branco.
Colunas: **`Participante;Tipo;Cargo;Incluído;Pontos;Dias presentes;Valor (R$)`**
- uma linha por item, na ordem recebida (`ingestao_fechamento_exportar` / `comissao_detalhe` já ordenam);
- `Participante` = `funcionario_nome` (snapshot); `Tipo` = `Funcionário` ou `Extra`; `Cargo` = `cargo` ou vazio; `Incluído` = `Sim`/`Não`;
  `Pontos` = `numeroCsv(pontos, 2)`; `Dias presentes` = `dias_presentes` (inteiro); `Valor (R$)` = `centavosCsv(valor_centavos)`.
- linha final: **`Total;;;;<Σ pontos dos incluídos, numeroCsv 2>;<Σ dias presentes dos incluídos>;<centavosCsv(Σ valor_centavos de todos os itens)>`**.
- Escape, BOM, `\r\n`, `numeroCsv`/`centavosCsv` e nome do arquivo: §13 sem mudança. Sem a coluna "Pontos extras" e sem "Pontos efetivos".

### E.5 Gastos do período — `gastos_periodo(p_inicio date, p_fim date, p_empresa uuid default null) returns jsonb`
`[api]` G A M. Máx. **366 dias** (`Período máximo de 366 dias`). Formato exato:
```json
{
  "empresa_id": "uuid", "inicio": "2026-09-01", "fim": "2026-09-30",
  "totais": { "diarias_pagas": 30000, "diarias_a_pagar": 15000, "diarias": 45000, "diarias_qtd": 3,
              "diarias_extras": 33000, "diarias_funcionarios": 12000,
              "comissoes_fechadas": 144001, "comissoes_previstas": 120000,
              "total": 189001, "total_com_previsto": 309001 },
  "por_pessoa": [ { "chave": "x:<uuid>", "tipo": "extra", "funcionario_id": null, "extra_id": "uuid", "nome": "Marcos Freitas",
                    "diarias_qtd": 2, "diarias_pagas": 18000, "diarias_a_pagar": 18000,
                    "comissoes_fechadas": 25669, "comissoes_previstas": 0, "total": 61669 } ],
  "por_dia": [ { "data": "2026-09-01", "diarias_pagas": 0, "diarias_a_pagar": 0,
                 "comissoes_fechadas": 0, "comissoes_previstas": 0, "total": 0 } ],
  "fechamentos": [ { "id": "uuid", "titulo": "Comissão 01/09 a 03/09/2026", "status": "fechado", "modo_rateio": "diario",
                     "data_inicio": "2026-09-01", "data_fim": "2026-09-03", "base_distribuivel_centavos": 144001,
                     "valor_no_periodo_centavos": 144001 } ]
}
```
- Diárias (extras e funcionários) por `data ∈ [inicio, fim]`; `pagas` = `pago`, `a_pagar` = não pago; `diarias_extras`/`diarias_funcionarios` = por tipo.
- Comissões — **modo diário: pelo detalhe diário**: cada `comissao_rateio_itens_dia.valor_centavos` cai **no próprio dia** e só conta se
  o dia estiver em `[inicio, fim]` (fechamento que cruza o período conta só a parte de dentro). **Modo período**: o valor inteiro do item
  cai em `data_fim` e conta se `data_fim ∈ [inicio, fim]` (como na v1). `fechado` → `comissoes_fechadas`; `rascunho` → `comissoes_previstas`.
- `total = diarias + comissoes_fechadas`; `total_com_previsto = total + comissoes_previstas`. Em `por_pessoa`/`por_dia`,
  `total = diarias_pagas + diarias_a_pagar + comissoes_fechadas` (previsto à parte).
- `por_pessoa`: `chave` = `'f:' || funcionario_id`, `'x:' || extra_id`, ou `'n:' || lower(btrim(nome))` (item snapshot sem id);
  `tipo` `funcionario`/`extra`; `nome` = nome atual do cadastro (ou o snapshot); ordem `total desc, nome collate "C", chave`.
  Só aparecem pessoas com algum valor (> 0 em qualquer coluna) ou diária no período.
- `por_dia`: **um registro por dia** do período (zeros incluídos), em ordem. `fechamentos`: os que contribuem (diário que cruza o
  período; período com `data_fim` dentro), `valor_no_periodo_centavos` = quanto dele caiu no período; ordem `data_fim, titulo, id`.
  Rascunhos sobrepostos somam todos em `comissoes_previstas` (é uma previsão).

### E.6 Mensagens novas (v2)
`Extra não encontrado` · `Extra inativo` · `Extra de outra empresa` · `Extra com dias lançados: desative em vez de excluir` ·
`Informe o extra ou o funcionário` · `Extra já tem dia lançado em DD/MM/AAAA` · `Diária de funcionário não tem pontos` · `Tipo inválido` ·
`Modo de rateio inválido` · `Extra sem dias lançados no período` · `Há dias com serviço sem participantes para ratear`.
Removidas: `Pontos extras inválidos`, `Informe o funcionário ou o nome`. Reaproveitadas: `Pontos inválidos`, `Valor inválido`,
`Informe o nome`, `Informe o valor da diária`, `Data fora do limite`, `Diária não encontrada`, `Período de comissão já fechado`.

---

## R. Reservas (Tagme)

A Tagme **não** tem API pública (só parceiros, sob contrato). O banco fica pronto e genérico: tipo de integração `tagme`
(o N8N busca na API quando houver contrato e grava por `ingestao_reservas`), cadastro manual e importação de CSV pelo front.

### R.1 Integração `tagme` (ajustes em §5/§11.1/§12)
- `integracoes.tipo` ∈ `('zig', 'controlid_acesso', 'controlid_rep', 'tagme')`.
- `parametros` padrão: `{"url_base": "", "restaurante_id": "", "dias_retroativos": 1, "dias_a_frente": 7}`.
- `segredos` permitidos: `token`, `cliente_id`, `cliente_segredo`.
- `sync_solicitacoes.escopo` ganha `reservas`; `sync_escopo_compativel`: `tudo` → também `tagme`; `reservas` → só `tagme`.
  `sync_solicitar(p_escopo => 'reservas')` funciona como os demais (período opcional, máx. 31 dias).
- `sync_execucoes.tipo` ganha `tagme_importar`.
- `ingestao_integracoes_ativas` e `ingestao_integracao_config` não mudam: `tagme` aparece com `parametros`, `segredos`, `cursor`,
  `fuso`, `virada_dia`, `dia_trabalho_atual` como os demais (sem `lojas`).
- Despacho N8N: `tagme` × `tudo`/`reservas` → subfluxo de reservas (janela padrão `[hoje − dias_retroativos, hoje + dias_a_frente]`).

### R.2 DDL
```sql
-- ===================================================== reservas  [api:leitura]  (select direto: só G A M)
create table if not exists public.reservas (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  integracao_id  uuid references public.integracoes (id) on delete set null,     -- origem 'tagme'
  origem         text not null check (origem in ('tagme', 'manual', 'importacao')),
  id_externo     text,                         -- obrigatório em 'tagme'; opcional em 'importacao'; null em 'manual'
  data           date not null,                -- data da reserva (calendário local)
  horario        time,                         -- null = sem horário
  nome_cliente   text not null check (btrim(nome_cliente) <> ''),
  pessoas        int not null default 1 check (pessoas between 1 and 500),
  status         text not null default 'confirmada'
                 check (status in ('confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu')),
  area           text,
  mesa           text,
  observacao     text,
  telefone       text,                         -- dado pessoal: só G A M
  email          text,                         -- dado pessoal: só G A M
  criado_por     uuid references public.perfis (id) on delete set null,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  importado_em   timestamptz,                  -- última gravação pela ingestão/importação
  constraint reservas_externa_uk unique (empresa_id, origem, id_externo)
);
-- índices: (empresa_id, data, horario), (integracao_id), (criado_por)
```
**Leitura** não tem `select` na tabela (RLS G A M): usa `reservas_listar`/`painel_do_dia`, que devolvem `telefone`/`email` = `null`
para quem não pode operar. O front DEVE ler reservas sempre por `reservas_listar`.
Status (rótulos do front): `confirmada` Confirmada · `pendente` Pendente · `cancelada` Cancelada · `sentada` Sentada ·
`concluida` Concluída · `nao_compareceu` Não compareceu.

### R.3 RPCs (`[api]`)
| assinatura | quem | regra |
|---|---|---|
| `reserva_criar(p_data date, p_horario time, p_nome_cliente text, p_pessoas int default 1, p_telefone text default null, p_area text default null, p_mesa text default null, p_observacao text default null, p_status text default 'confirmada', p_email text default null, p_empresa uuid default null) returns uuid` | G A M | origem `manual`. `Informe a data`, `Informe o nome do cliente`, `Número de pessoas inválido` (1..500), `Status de reserva inválido` |
| `reserva_atualizar(p_reserva uuid, p_data date, p_horario time, p_nome_cliente text, p_pessoas int, p_telefone text, p_area text, p_mesa text, p_observacao text, p_status text, p_email text) returns void` | G A M | substitui tudo; origem `tagme` → `Reserva da Tagme: só o status pode ser alterado`; `Reserva não encontrada` |
| `reserva_mudar_status(p_reserva uuid, p_status text) returns void` | G A M | qualquer origem (numa reserva `tagme` a próxima sincronização pode sobrescrever) |
| `reserva_cancelar(p_reserva uuid) returns void` | G A M | = status `cancelada` |
| `reserva_excluir(p_reserva uuid) returns void` | G A M | só `manual`/`importacao` (`Reserva da Tagme não pode ser excluída`) |
| `reservas_listar(p_inicio date, p_fim date default null, p_status text[] default null, p_empresa uuid default null) returns table(id uuid, origem text, data date, horario time, nome_cliente text, pessoas int, status text, area text, mesa text, observacao text, telefone text, email text, criado_em timestamptz, atualizado_em timestamptz)` | L G A M | `p_fim` padrão = `p_inicio`; máx. 93 dias; ordem `data, horario nulls last, nome_cliente, id`; L: `telefone`/`email` null |
| `reservas_importar(p_linhas jsonb, p_empresa uuid default null) returns jsonb` | G A M | importação de CSV pelo front (abaixo) |
| `ingestao_reservas(p_integracao uuid, p_inicio date, p_fim date, p_itens jsonb) returns jsonb` | `[servico]` | N8N (abaixo) |

**`reservas_importar`** — o front lê o CSV e manda as linhas já como objetos (máx. 2000, `Lote maior que 2000 itens`;
não-array → `Lista de itens inválida`):
```json
[ { "id_externo": "A-123", "data": "2026-11-12", "horario": "20:30", "nome": "Maria Lima", "pessoas": 4,
    "telefone": "11999990000", "email": null, "status": "confirmada", "area": "Varanda", "mesa": "12", "observacao": "Aniversário" } ]
```
`data` aceita `AAAA-MM-DD` ou `DD/MM/AAAA`; `horario` `HH:MM`/`HH:MM:SS` ou vazio; `pessoas` vazio → 1; `status` vazio → `confirmada`.
Origem `importacao`. Com `id_externo` → *upsert* por `(empresa, 'importacao', id_externo)`; sem → sempre insere.
Retorno `{lidos, gravados, ignorados, inseridos, atualizados, erros: [{indice, motivo}]}` (máx. 20 erros; `indice` base 0).
Motivos: `item inválido` · `data inválida` · `horário inválido` · `informe o nome` · `pessoas inválido` · `status inválido` · `id repetido`.
Colunas sugeridas para o modelo de CSV do front (§13, separador `;`): `Data;Horário;Nome;Pessoas;Telefone;E-mail;Status;Área;Mesa;Observação;Código`.

**`ingestao_reservas(p_integracao, p_inicio, p_fim, p_itens)`** — valida a integração (`Integração não encontrada`, `Integração inativa`,
`Tipo de integração incompatível` se não for `tagme`), `p_inicio`/`p_fim` obrigatórios (máx. 62 dias), `p_itens` array (≤ 2000).
Item (o N8N já traduz a resposta da Tagme para este formato):
```json
{ "id_externo": "tg-98123", "data": "2026-11-12", "hora": "20:30", "nome": "Maria Lima", "telefone": "11999990000",
  "email": null, "pessoas": 4, "status": "confirmada", "observacao": null, "area": null, "mesa": null,
  "origem": "tagme", "bruto": { } }
```
- `id_externo` obrigatório (`id_externo ausente`); `data` `AAAA-MM-DD` (`data inválida`); `hora` `HH:MM`|null (`horário inválido`);
  `nome` obrigatório (`informe o nome`); `pessoas` 1..500, null → 1 (`pessoas inválido`); `status` um dos seis, null → `confirmada`
  (`status inválido` — o N8N mapeia os status da Tagme); `id_externo` repetido no lote → `id repetido`.
  `origem` é ignorado (sempre `tagme`); **`bruto` não é gravado** (LGPD: minimização).
- *Upsert* por `(empresa, 'tagme', id_externo)` (atualiza todos os campos, `integracao_id`, `importado_em`).
- **Substitui a janela**: reservas `tagme` da empresa com `data ∈ [p_inicio, p_fim]` cujo `id_externo` não veio no lote são **apagadas**
  (`removidos`). Itens válidos com data fora da janela são gravados normalmente (não removem nada fora dela). Lote vazio é válido.
  Trava `pg_advisory_xact_lock(hashtextextended('mdg:reservas:<empresa>', 0))` (cargas simultâneas em fila).
- `integracoes.cursor` = `{"ultimo_inicio": "AAAA-MM-DD", "ultimo_fim": "AAAA-MM-DD"}`.
- Retorno: `{lidos, gravados, ignorados, inseridos, atualizados, removidos, erros}` (§11.2).

### R.4 Painel — blocos novos em `painel_do_dia` (campos existentes inalterados)
```json
"reservas": {
  "total": 12, "pessoas": 48, "canceladas": 1, "nao_compareceu": 0, "sentadas": 3, "tem_tagme": false,
  "proximas": [ { "id": "uuid", "horario": "20:30:00", "nome_cliente": "Maria Lima", "pessoas": 4, "status": "confirmada",
                  "area": "Varanda", "mesa": "12", "observacao": null, "origem": "manual", "telefone": "11999990000|null" } ]
},
"ocorrencias": { …formato de ocorrencias_resumo(30)… } | null
```
- Reservas com `data = dia_trabalho` (hoje). `total`/`pessoas`: status ≠ `cancelada`; `canceladas`, `nao_compareceu`, `sentadas`: contagem por status.
- `proximas`: status `confirmada`/`pendente`, com `horario` null ou instante (`data + horario` no fuso da empresa) ≥ `agora() − 30 min`;
  ordem `horario nulls last, nome_cliente`; até 10. `telefone` = null para leitura. `tem_tagme` = existe integração `tagme` ativa.
- `ocorrencias`: `null` para leitura (dado sensível); G A M recebem o resumo de 30 dias.

---

## M. Mensagens de erro novas (texto exato)
`Data no futuro` · `Tipo de ocorrência inválido` · `Ocorrência não encontrada` · `Dias de suspensão inválidos (1 a 30)` ·
`Início da suspensão inválido` · `Já existe abono para o funcionário em DD/MM/AAAA` · `Dia com suspensão: altere pela ocorrência` ·
`Limite de 10 anexos por ocorrência` · `Anexo inválido` · `Anexo não encontrado no armazenamento` · `Anexo já registrado` ·
`Anexo não encontrado` · `Período de comissão já fechado` · as de extras v2 (§E.6) ·
`Informe o valor da diária` · `Valor inválido` · `Data fora do limite` · `Diária não encontrada` · `Informe o nome do cliente` ·
`Número de pessoas inválido` · `Status de reserva inválido` · `Reserva não encontrada` ·
`Reserva da Tagme: só o status pode ser alterado` · `Reserva da Tagme não pode ser excluída`.
Reaproveitadas: `Sem permissão`, `Informe a empresa`, `Informe o motivo`, `Informe a data`, `Funcionário não encontrado`,
`Funcionário de outra empresa`, `Período inválido`, `Período máximo de N dias`, `Lançamento não encontrado`, `Lista de itens inválida`,
`Lote maior que 2000 itens`, `Tipo de abono inválido`, as de integração (§11.2).

## P. Matriz de acesso (extensão do §3.2)
| tabela | etiqueta | select | escrita |
|---|---|---|---|
| funcionario_ocorrencias, funcionario_ocorrencia_anexos | `[api:leitura]` | G A M | RPC (G A M) |
| extras | `[api:leitura]` | G A M (L não vê valores nem dados pessoais) | RPC (G A M) |
| comissao_rateio_dias, comissao_rateio_itens_dia | `[api:leitura]` | G A M | só o cálculo (gatilho: fechado = imutável) |
| funcionario_valores_diaria, diarias | `[api:leitura]` | G A M | RPC (G A M) |
| reservas | `[api:leitura]` | G A M (L via `reservas_listar`, sem telefone/e-mail) | RPC (G A M) / ingestão |
