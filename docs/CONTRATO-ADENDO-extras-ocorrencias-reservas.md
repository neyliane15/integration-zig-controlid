# Adendo ao contrato — Ocorrências disciplinares, Extras (pontos extras, diárias, gastos) e Reservas (Tagme)

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
| `…0220_comissoes.sql` (ajuste) | `comissao_pontos_extras`, `comissao_itens.pontos_extras`, cálculo com extras (§E.1) |
| `…0240_painel.sql` (ajuste) | blocos `reservas` e `ocorrencias` no `painel_do_dia` |
| `…0250_ocorrencias.sql` (nova) | ocorrências, anexos, bucket `funcionarios-documentos`, RPCs |
| `…0260_extras.sql` (nova) | valor padrão de diária, `diarias`, `gastos_periodo`, RPCs dos extras |
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

## E. Extras

### E.1 Pontos extras de comissão

```sql
-- ================================================ comissao_pontos_extras  [api:leitura]  (select: G A M)
create table if not exists public.comissao_pontos_extras (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,    -- gatilho: do funcionário
  funcionario_id   uuid not null references public.funcionarios (id) on delete cascade,
  data             date not null,
  pontos           numeric(8,2) not null check (pontos > 0 and pontos <= 9999.99),
  motivo           text not null check (btrim(motivo) <> ''),    -- ex.: 'Cobriu folga', 'Meta batida'
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now()
);
-- comissao_itens ganha:  pontos_extras numeric(10,2) not null default 0
```

**Regra nova do §9** (substitui os passos 4–6):
- `extras_i = Σ comissao_pontos_extras.pontos` do funcionário com `data ∈ [data_inicio, data_fim]` (qualquer loja — extras não têm loja).
- A cada cálculo (criar, editar, recalcular, definir/remover item, fechar): (a) funcionários da empresa com `extras > 0` no período que
  ainda não têm item **entram** com `pontos = 0`, `incluido = true` (snapshot de nome/cargo) — mesmo sem pontos base, inativo ou
  `participa_comissao = false` (o lançamento explícito vale); (b) `pontos_extras` de todo item com `funcionario_id` é relido.
  Item com `funcionario_id null` (funcionário excluído) mantém o último `pontos_extras`.
- `base_i = pontos_i` ou, com `proporcional_dias`, `round(pontos_i × dias_trabalhados_i / dias_periodo, 6)` (como antes).
- **`pontos_efetivos_i = incluido_i ? base_i + pontos_extras_i : 0`** — os extras **não** são proporcionalizados.
- Soma, valor do ponto, maior resto exato e desempate: **sem mudança** (§9 passos 7–9, sobre `pontos_efetivos`).
- `comissao_remover_item` de funcionário que tem extras no período **não apaga**: marca `incluido = false` (senão ele voltaria no
  próximo cálculo). Para tirá-lo de vez, exclua os extras.
- Lançar/excluir extra cuja `data` está dentro de um fechamento **fechado** da empresa → `Período de comissão já fechado` (22023).
  Rascunhos **não** são recalculados sozinhos: o front chama `comissao_recalcular` (ou mostra "recalcule para incluir os extras").

**Para o front replicar** (`web/src/lib/comissao.ts`): a entrada de cada participante ganha `pontosExtras` (número com 2 casas);
em escala 10⁶: `pe6 = incluido ? (proporcional ? dividirArredondando(pontos6 × dias, diasPeriodo) : pontos6) + escalar(pontosExtras, 2) × 10⁴ : 0`.
O resto do algoritmo não muda. Participante só com extras: `pontos = 0`.

**Vetores (banco e vitest)** — base `796000` do exemplo do §9 (bruto 995000, retenção 20%):
1. Exemplo do §9 sem extras: valores inalterados (209474, 209474, 125684, 167579, 83789).
2. Proporcional (30 dias, Eva 15 dias, demais 30) **+ Carla 1,5 extra**: pe Ana 10, Bruno 10, Carla 7,5, Davi 8, Eva 2 → soma 37,5;
   exatos 212266,67 / 212266,67 / 159200 / 169813,33 / 42453,33; pisos 795998, resto 2 → Ana e Bruno:
   **Ana 212267, Bruno 212267, Carla 159200, Davi 169813, Eva 42453** (Σ 796000).
3. Não proporcional **+ Eva 1 extra + Fábio Nunes (pontos 0, só 3 extras)**: pe 10, 10, 6, 8, 5, 3 → soma 42;
   pisos 189523, 189523, 113714, 151619, 94761, 56857 (Σ 795997), resto 3 → Eva (0,905), Ana (0,810), Bruno (0,810):
   **Ana 189524, Bruno 189524, Carla 113714, Davi 151619, Eva 94762, Fábio 56857** (Σ 796000).

RPCs (`[api]`, G A M):
| assinatura | regra |
|---|---|
| `comissao_extra_lancar(p_funcionario uuid, p_data date, p_pontos numeric, p_motivo text) returns uuid` | `Pontos extras inválidos` (≤ 0 ou > 9999,99 ou mais de 2 casas), `Informe o motivo`, `Informe a data`, `Período de comissão já fechado` |
| `comissao_extra_excluir(p_extra uuid) returns void` | `Lançamento não encontrado`, `Período de comissão já fechado` |
| `comissao_extras_listar(p_inicio date, p_fim date, p_funcionario uuid default null, p_empresa uuid default null) returns table(id uuid, funcionario_id uuid, funcionario_nome text, cargo text, data date, pontos numeric, motivo text, criado_por_nome text, criado_em timestamptz, fechado boolean)` | máx. 366 dias; `fechado` = data dentro de fechamento fechado; ordem `data desc, criado_em desc` |

**CSV de comissão (§13, front e N8N idênticos)** — nova coluna entre "Dias trabalhados" e "Pontos efetivos":
`Funcionário;Cargo;Incluído;Pontos;Dias trabalhados;Pontos extras;Pontos efetivos;Valor (R$)`
- `Pontos extras` = `numeroCsv(pontos_extras, 2)` (`0` quando zero, `1,5`, `3`).
- Linha final: `Total;;;<Σ pontos dos incluídos>;;<Σ pontos extras dos incluídos>;<Σ pontos efetivos>;<base distribuível>`.
- Preâmbulo sem mudança. `ingestao_fechamento_exportar` já devolve `pontos_extras` em cada item (todas as colunas de `comissao_itens`).

### E.2 Diárias

```sql
-- ======================================== funcionario_valores_diaria  [api:leitura]  (select: G A M)
-- Valor PADRÃO da diária do funcionário (fora de `funcionarios` porque a leitura enxerga funcionarios).
create table if not exists public.funcionario_valores_diaria (
  funcionario_id         uuid primary key references public.funcionarios (id) on delete cascade,
  empresa_id             uuid not null references public.empresas (id) on delete cascade,   -- gatilho
  valor_diaria_centavos  bigint not null check (valor_diaria_centavos between 0 and 100000000),
  atualizado_por         uuid references public.perfis (id) on delete set null,
  atualizado_em          timestamptz not null default now()
);

-- ===================================================== diarias  [api:leitura]  (select: G A M; L NÃO vê)
create table if not exists public.diarias (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  funcionario_id   uuid references public.funcionarios (id) on delete set null,   -- null = avulso (freelancer sem cadastro)
  pessoa_nome      text not null check (btrim(pessoa_nome) <> ''),   -- snapshot do nome do funcionário ou nome livre
  data             date not null,
  funcao           text,                                             -- padrão: cargo do funcionário
  valor_centavos   bigint not null check (valor_centavos between 0 and 100000000),
  observacao       text,
  pago             boolean not null default false,
  pago_em          date,                                             -- null se não pago
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  constraint diarias_pagamento check (pago or pago_em is null)
);
```
Regras: com `p_funcionario` → mesma empresa, `pessoa_nome` = nome atual do funcionário (o `p_pessoa_nome` é ignorado), `funcao`
padrão = cargo, `valor` padrão = `funcionario_valores_diaria`; sem funcionário → `p_pessoa_nome` obrigatório
(`Informe o funcionário ou o nome`). Sem valor e sem padrão → `Informe o valor da diária`. `Valor inválido` fora de 0..100000000.
`p_pago = true` e `p_pago_em null` → `pago_em` = dia de trabalho atual; `p_pago = false` → `pago_em = null`.
Data em `[hoje − 366, hoje + 62]` (`Data fora do limite`).

RPCs (`[api]`, G A M):
| assinatura | retorno |
|---|---|
| `funcionario_definir_valor_diaria(p_funcionario uuid, p_valor_centavos bigint) returns void` | `null` remove o padrão |
| `funcionario_valores_diaria_listar(p_empresa uuid default null) returns table(funcionario_id uuid, valor_diaria_centavos bigint)` | |
| `diaria_lancar(p_data date, p_funcionario uuid default null, p_pessoa_nome text default null, p_funcao text default null, p_valor_centavos bigint default null, p_observacao text default null, p_pago boolean default false, p_pago_em date default null, p_empresa uuid default null) returns uuid` | id |
| `diaria_atualizar(p_diaria uuid, p_data date, p_funcionario uuid, p_pessoa_nome text, p_funcao text, p_valor_centavos bigint, p_observacao text, p_pago boolean, p_pago_em date) returns void` | substitui tudo; `Diária não encontrada` |
| `diaria_marcar_paga(p_diaria uuid, p_pago boolean, p_pago_em date default null) returns void` | |
| `diaria_excluir(p_diaria uuid) returns void` | |
| `diarias_listar(p_inicio date, p_fim date, p_funcionario uuid default null, p_pago boolean default null, p_empresa uuid default null) returns table(id uuid, data date, funcionario_id uuid, pessoa_nome text, avulso boolean, funcao text, valor_centavos bigint, observacao text, pago boolean, pago_em date, criado_por_nome text, criado_em timestamptz)` | máx. 366 dias; ordem `data desc, pessoa_nome, criado_em` |

### E.3 Gastos totais por período — `gastos_periodo(p_inicio date, p_fim date, p_empresa uuid default null) returns jsonb`
`[api]` G A M. Máx. **366 dias** (`Período máximo de 366 dias`). Formato exato:
```json
{
  "empresa_id": "uuid", "inicio": "2026-11-01", "fim": "2026-11-30",
  "totais": { "diarias_pagas": 30000, "diarias_a_pagar": 15000, "diarias": 45000, "diarias_qtd": 3,
              "comissoes_fechadas": 796000, "comissoes_previstas": 120000,
              "total": 841000, "total_com_previsto": 961000 },
  "por_pessoa": [ { "chave": "f:<uuid>", "funcionario_id": "uuid|null", "nome": "Ana Souza", "avulso": false,
                    "diarias_qtd": 1, "diarias_pagas": 15000, "diarias_a_pagar": 0,
                    "comissoes_fechadas": 209474, "comissoes_previstas": 0, "total": 224474 } ],
  "por_dia": [ { "data": "2026-11-01", "diarias_pagas": 0, "diarias_a_pagar": 0,
                 "comissoes_fechadas": 0, "comissoes_previstas": 0, "total": 0 } ],
  "fechamentos": [ { "id": "uuid", "titulo": "Comissão 01/11 a 30/11/2026", "status": "fechado",
                     "data_inicio": "2026-11-01", "data_fim": "2026-11-30", "base_distribuivel_centavos": 796000 } ]
}
```
- Diárias: por `data ∈ [inicio, fim]`; `pagas` = `pago = true`, `a_pagar` = `pago = false`.
- Comissões: fechamentos com `data_fim ∈ [inicio, fim]` (qualquer loja); `fechado` → `comissoes_fechadas` (Σ `valor_centavos` dos itens);
  `rascunho` → `comissoes_previstas`. No `por_dia` a comissão cai no dia `data_fim` do fechamento.
- `total = diarias + comissoes_fechadas`; `total_com_previsto = total + comissoes_previstas`. Em `por_pessoa`/`por_dia`,
  `total = diarias_pagas + diarias_a_pagar + comissoes_fechadas` (previsto à parte).
- `por_pessoa`: `chave` = `'f:' || funcionario_id` (diária de funcionário ou item com funcionário) ou `'a:' || lower(btrim(nome))`
  (avulso, ou item cujo funcionário foi excluído); `nome` = nome atual do funcionário (ou o snapshot); ordem `total desc, nome`.
  Só aparecem pessoas com algum valor (> 0 em qualquer coluna) ou diária no período.
- `por_dia`: **um registro por dia** do período (zeros incluídos), em ordem. `fechamentos`: ordem `data_fim, titulo`.

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
`Anexo não encontrado` · `Pontos extras inválidos` · `Período de comissão já fechado` · `Informe o funcionário ou o nome` ·
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
| comissao_pontos_extras | `[api:leitura]` | G A M | RPC (G A M) |
| funcionario_valores_diaria, diarias | `[api:leitura]` | G A M | RPC (G A M) |
| reservas | `[api:leitura]` | G A M (L via `reservas_listar`, sem telefone/e-mail) | RPC (G A M) / ingestão |
