# Adendo ao contrato — Escala rotativa (5x2, modelo Macaw) ligada ao ponto

> **Versão 3** — §S.11: **faltas** na escala (código FJ/FI, `escala_ajustar` com status `falta_justificada`/`falta_injustificada`)
> e a escala como fonte de **presença da comissão** nos dias sem ponto (adendo extras §E.7). Migração `…0290_comissao_presenca.sql`.
>
> **Versão 2** — inclui o pedido do cliente para a empresa real "Macaw Camboinhas": `escala_aplicar_modelo_macaw` monta o modelo
> inteiro (cria funcionários provisórios para as posições sem funcionário), `escala_adicionar_funcionario` cadastra e põe na escala
> numa chamada só, e a escala funciona **sem nenhuma batida nem integração** de ponto (§S.6).

Dono: **backend** (banco). Implementa contra este adendo: **frontend** (`web/`). Complementa `docs/CONTRATO.md`; onde houver
conflito, **este adendo vale**. Convenções de sempre (§2): etiquetas no `comment on`, RLS em tudo, RPC `security definer` com
`search_path`, `agora()`, erros `raise exception '<texto exato>' using errcode` (42501 permissão, 22023 valor, P0002 não encontrado,
23505 duplicado). Papéis: **L** leitura, **G** gerente, **A** administrador, **M** master. "G A M" = `pode_operar(empresa)`.
Referência do cliente: `docs/referencias/escala-macaw-v3.html`.

| arquivo | conteúdo |
|---|---|
| `…0200_ponto.sql` (ajuste) | coluna `ponto_abonos.escala_ajuste_id`; `ponto_calcular_dia` consulta a escala (§S.5); `ponto_abonar`/`ponto_remover_abono` recusam dia de férias da escala |
| `…0280_escala.sql` (nova) | tabelas, regra do rodízio, RPCs, férias → abono, reapuração |
| testes | `supabase/testes/76_escala.sql`; `92_isolamento.sql` cobre as tabelas novas |
| carga demo | `supabase/seed/40_demo_escala.sql` (Bar Bossa Nova: Salão, Bar, Cozinha com os 5 funcionários da demo) |

---

## S.1 Conceitos

- **Setor** (Salão, Maître, Areia, Bar, ASG, Cozinha…): grupo de funcionários com ordem de exibição.
- **Membro**: um funcionário **cadastrado** num setor (no máximo um setor por funcionário). Tem as **folgas da semana base**
  (dias da semana, **0 = SEG … 6 = DOM** — atenção: diferente do `dow` do Postgres), a **chegada padrão** (opcional) e:
  - um **caminho** de rodízio (1, 2…) + **posição** nesse caminho, **ou**
  - nenhum caminho = **folga fixa** (ex.: Chef, Gerente): todas as semanas folga nos seus dias base.
- **Data-âncora** (por empresa): uma **segunda-feira**. A semana que começa nela é a **semana 0**; a semana seguinte é a 1, a anterior
  é a −1. O rodízio é **contínuo** a partir dela (não recomeça no mês). **Fase** (empresa) + **fase do setor**: deslocamento inteiro
  somado ao número da semana para realinhar o rodízio sem mexer na âncora.
- **Ajuste** do dia (funcionário × data): status `trabalha` | `folga` | `ferias` e/ou horário de **chegada** do dia. Sem ajuste =
  **automático** (regra do rodízio). Férias são ajustes (um por dia; `escala_ajustar_periodo` marca vários dias).
- Status de um dia: `trabalha`, `folga`, `ferias` ou **`fora`** = fora da escala (antes da âncora, antes da admissão ou depois do
  desligamento do funcionário). Dia `fora` não aceita ajuste e não afeta o ponto.

## S.2 Regra do rodízio (o banco e a prévia do front usam exatamente isto)

Para o membro `m` no dia `D` (dia de trabalho):
1. `seg(D) = D − (isodow(D) − 1)` (segunda-feira da semana de D); `w = (seg(D) − ancora) / 7` (inteiro, pode ser negativo).
2. `D < ancora` ou `D` fora do vínculo do funcionário → **`fora`**.
3. Ajuste de status no dia → esse status (`origem = 'ajuste'`).
4. Senão (automático): se `m` está num caminho `P` (membros do mesmo setor com o mesmo `caminho`, ordenados por `posicao`, `id`),
   `n = |P|`, `k` = índice de `m` em `P` (0-based), `f = fase_empresa + fase_setor`,
   `alvo = P[((k + w + f) mod n + n) mod n]` (mod sempre positivo). Sem caminho: `alvo = m`.
   **folga** se `(isodow(D) − 1) ∈ alvo.folgas_base`, senão **trabalha** (`origem = 'auto'`).
   Ou seja: a cada semana cada pessoa assume as folgas base da **próxima posição** do caminho, voltando ao início.
5. Chegada do dia (só quando `trabalha`): `ajuste.chegada` → senão `m.chegada_padrao` → senão `null` (o ponto usa a entrada da jornada).

### Exemplo numérico — setor Salão do modelo, âncora **2026-11-02** (seg), fase 0
Caminho 1: pos 1 Garçom 1 (QUA,QUI) · pos 2 Garçom 2 (QUA,QUI) · pos 3 Garçom 3 (QUA,QUI) · pos 4 Cumim 2 (QUA,DOM).
Caminho 2: pos 1 Garçom 4 (SEG,TER) · pos 2 Garçom 5 (SEG,TER) · pos 3 Garçom 6 (SEG,TER) · pos 4 Cumim 1 (TER,DOM).

| semana (segunda) | w | Garçom 1 (k=0) | Cumim 2 (k=3) | Garçom 4 (k=0) | Cumim 1 (k=3) |
|---|---|---|---|---|---|
| 02/11/2026 | 0 | pos1 → QUA 04, QUI 05 | pos4 → QUA 04, DOM 08 | SEG 02, TER 03 | TER 03, DOM 08 |
| 09/11 | 1 | pos2 → QUA 11, QUI 12 | pos1 → QUA 11, QUI 12 | pos2 → SEG 09, TER 10 | pos1 → SEG 09, TER 10 |
| 16/11 | 2 | pos3 → QUA 18, QUI 19 | pos2 → QUA 18, QUI 19 | SEG 16, TER 17 | SEG 16, TER 17 |
| 23/11 | 3 | pos4 → QUA 25, **DOM 29** | pos3 → QUA 25, QUI 26 | pos4 → TER 24, DOM 29 | SEG 23, TER 24 |
| 30/11 | 4 ≡ 0 | QUA 02/12, QUI 03/12 | QUA 02/12, DOM 06/12 | SEG 30/11, TER 01/12 | TER 01/12, DOM 06/12 |
| 07/12 | 5 ≡ 1 | QUA 09/12, QUI 10/12 | QUA 09/12, QUI 10/12 | … | … |
| 01/02/2027 | **13 ≡ 1** | como na semana 1 | como na semana 1 | | |

- 01/11/2026 (domingo, antes da âncora) = `fora` para todos.
- Continuidade: a semana de 01/02/2027 é a 13 → posição k+1 (no modelo antigo, que recomeçava no mês, seria k+0).
- Fase 1 (empresa ou setor): toda semana anda uma posição a mais (a semana 0 fica como a 1 acima).
- "Na escala" de 04/11 no caminho 1: só Garçom 1, 2, 3 e Cumim 2 folgam (QUA) → 0 dos 4; caminho 2: 4 de 4 → Salão = 4.

## S.3 DDL (`…0280_escala.sql`)

```sql
-- ============================================ escala_config  [api:leitura]  (select: L G A M) — uma por empresa
create table if not exists public.escala_config (
  empresa_id     uuid primary key references public.empresas (id) on delete cascade,
  ancora         date not null check (extract(isodow from ancora) = 1),   -- segunda-feira (semana 0)
  fase           int  not null default 0 check (fase between -1000 and 1000),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
-- ============================================ escala_setores  [api:leitura]  (select: L G A M)
create table if not exists public.escala_setores (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  nome           text not null check (btrim(nome) <> ''),
  ordem          int  not null default 0,
  fase           int  not null default 0 check (fase between -1000 and 1000),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
-- unique (empresa_id, lower(btrim(nome)))  → 'Setor já existe' (23505)
-- ============================================ escala_membros  [api:leitura]  (select: L G A M)
create table if not exists public.escala_membros (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,     -- gatilho: do setor
  setor_id        uuid not null references public.escala_setores (id) on delete cascade,
  funcionario_id  uuid not null unique references public.funcionarios (id) on delete cascade,
  folgas_base     smallint[] not null default '{}',   -- 0=SEG..6=DOM, sem repetição, ordenado, até 6 dias
  chegada_padrao  time,
  caminho         smallint check (caminho between 1 and 20),           -- null = folga fixa
  posicao         smallint check (posicao between 1 and 99),           -- obrigatória com caminho; null sem caminho
  ordem           int not null default 0,                              -- ordem de exibição no setor
  modelo_posicao  text,          -- ex.: 'Salão|Garçom 1' — posição do modelo Macaw que este membro ocupa (idempotência)
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  constraint escala_membros_caminho check ((caminho is null) = (posicao is null))
);
-- unique (setor_id, caminho, posicao) where caminho is not null  → 'Posição já ocupada no caminho' (23505)
-- unique (empresa_id, modelo_posicao) where modelo_posicao is not null
-- ============================================ escala_ajustes  [api:leitura]  (select: G A M; L vê só por escala_mes)
create table if not exists public.escala_ajustes (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,    -- gatilho: do membro
  membro_id        uuid not null references public.escala_membros (id) on delete cascade,
  funcionario_id   uuid not null references public.funcionarios (id) on delete cascade, -- gatilho: do membro
  data             date not null,
  status           text check (status in ('trabalha', 'folga', 'ferias')),             -- null = automático
  chegada          time,                                                                -- null = chegada padrão
  motivo           text,
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (funcionario_id, data),
  constraint escala_ajustes_algo check (status is not null or chegada is not null)
);
-- em ponto_abonos (…0200): escala_ajuste_id uuid references escala_ajustes(id) on delete cascade (+ índice)
```
Escrita **só por RPC**. Remover um membro (ou o setor) apaga os ajustes dele e, em cascata, os abonos de férias da escala.

## S.4 Férias → abono
Todo ajuste com `status = 'ferias'` mantém **um** abono em `ponto_abonos` (`tipo = 'ferias'`, `funcionario_id`, `data`,
`motivo = 'Férias (escala)'` ou `'Férias (escala): <motivo>'`, `escala_ajuste_id`). Trocar o status (ou voltar a automático)
apaga o abono; o dia é reapurado. Consequência no ponto: igual a qualquer abono (previsto 0, sem alarmes, situação `abonado`,
`abono_tipo = 'ferias'`).
- Já existe abono **do funcionário** no dia (manual, atestado, suspensão…) → `Já existe abono para o funcionário em DD/MM/AAAA` (22023).
  Feriado da empresa toda não conflita.
- `ponto_abonar` de um funcionário num período com férias da escala, ou `ponto_remover_abono` de abono da escala →
  `Dia com férias na escala: altere pela escala` (22023). Suspensão num dia de férias da escala → a mensagem de conflito da ocorrência.

## S.5 Integração com o ponto (`ponto_calcular_dia`, §7.2 passo 2)
Vale só para funcionário que é **membro** e dia que **não é `fora`**; caso contrário nada muda (só jornada).
1. Abono no dia → como hoje (abono prevalece sobre a escala; inclui as férias da escala).
2. Status **`folga`** (automática ou ajustada) → não é dia escalado: `previsto = 0`, `esperadas = 0`, situação `folga`
   (mesmo sem jornada), **sem** `sem_batida_dia_escalado`; batidas no dia = hora extra (`saldo = trabalhado`), ímpar gera `batidas_impares`.
3. Status **`trabalha`** → dia escalado, com **duração, intervalo, nº de batidas e tolerâncias da jornada vigente**:
   - horários = `jornada_dias` do dia da semana; se a jornada não tem esse dia, usa o **primeiro dia cadastrado da jornada na ordem
     SEG→DOM** como modelo;
   - **chegada** da escala (do dia ou padrão) não nula → todos os horários esperados são **deslocados** para que a entrada seja a
     chegada (`Ei' = instante(D, chegada) + (Ei − E1)`, §2.4 para a chegada). Isso vale para o alarme de **`atraso`**, para escolher
     a **batida faltante** e para `esperadas` do espelho/ponto do dia;
   - sem jornada vigente → como hoje (`sem_escala`, sem alarme).
4. Status `ferias` sem abono não acontece (o abono é mantido junto); se acontecer, trata como folga.

Exemplo (testado): jornada 17:00/21:00/21:30/01:00, chegada da escala 18:00 → esperadas 18:00/22:00/22:30/02:00; batida 18:20 →
`atraso` 20 min (`Entrada 18:20 (20 min de atraso)`); batidas 18:01, 22:02, 02:05 → `batida_faltando` `volta_intervalo` (22:30).

**Reapuração**: toda RPC de escrita reapura os funcionários afetados nos dias afetados, limitados a **[hoje − 61, hoje]**
(62 dias; o dia corrente incluso). Configuração/setor/membros → membros envolvidos, de `max(âncora, hoje − 61)` a hoje; ajuste/troca →
só os dias mexidos. Dias mais antigos só mudam com `ponto_reapurar` (botão "Recalcular"). *(v3)* Comissão: nos dias **sem ponto** a presença
vem da escala (`trabalha` = presente; `ferias` nunca) — adendo extras §E.7.1; rascunhos são recalculados por `comissao_recalcular`;
o fechamento fechado é imutável → a escala nunca altera comissão fechada.

**Front de ponto** (`web/src/lib/ponto.ts`, prévia/fuzz): para membro da escala, use sempre `esperadas` devolvido pelo banco
(`ponto_espelho`/`ponto_dia_empresa`) — não recalcule a partir da jornada.

## S.6 Sem batidas e sem integração
A escala é um cadastro próprio: monta, lê, ajusta e exporta **sem** nenhuma batida, jornada ou integração de ponto. O ponto só a
usa para funcionários com **jornada vigente** (§S.5.3). Os funcionários provisórios criados pelo modelo Macaw (§S.7.8) e por
`escala_adicionar_funcionario` não ganham jornada → **nunca** geram alarme, saldo ou dia escalado; quando a empresa ligar o ponto,
o gerente atribui a jornada e a escala passa a valer na apuração.

## S.7 RPCs de escrita (todas `[api]`, G A M; leitura recebe `Sem permissão`)

| # | assinatura | retorno / regra |
|---|---|---|
| 1 | `escala_configurar(p_ancora date, p_fase int default 0, p_empresa uuid default null) returns jsonb` | `{"empresa_id","ancora":"AAAA-MM-DD","fase":0}`. Âncora não segunda → `A data-âncora deve ser uma segunda-feira`; `Informe a data`; fase fora de −1000..1000 → `Fase inválida`. **Ajustes com data < nova âncora são apagados** (e seus abonos). |
| 2 | `escala_salvar_setor(p_nome text, p_ordem int default null, p_fase int default 0, p_setor uuid default null, p_empresa uuid default null) returns uuid` | cria (`p_setor` null) ou altera. `p_ordem null` = último (cria) / mantém (altera). Sem configuração → cria com âncora = segunda da semana atual, fase 0. `Informe o nome`, `Setor já existe` (23505), `Setor não encontrado` (P0002), `Fase inválida` |
| 3 | `escala_excluir_setor(p_setor uuid) returns void` | apaga setor, membros e ajustes; reapura |
| 4 | `escala_salvar_membro(p_setor uuid, p_funcionario uuid, p_folgas_base smallint[] default '{}', p_chegada_padrao time default null, p_caminho smallint default null, p_posicao smallint default null, p_ordem int default null) returns uuid` | upsert por funcionário (move de setor mantendo os ajustes); id do membro. `p_caminho` informado e `p_posicao null` → próxima posição livre do caminho. `Funcionário não encontrado` (P0002), `Funcionário de outra empresa`, `Folgas inválidas`, `Caminho inválido`, `Posição inválida`, `Posição já ocupada no caminho` (23505) |
| 5 | `escala_definir_membros(p_setor uuid, p_membros jsonb) returns int` | **substitui** a lista do setor (reordenar caminhos sem conflito de posição). `p_membros = [{"funcionario_id","folgas_base":[2,3],"chegada_padrao":"17:00"\|null,"caminho":1\|null,"posicao":1\|null}]`; `ordem` = índice na lista; quem saiu da lista sai da escala (perde os ajustes). Funcionário repetido → `Funcionário repetido na lista`; formato → `Lista de membros inválida`. Retorna nº de membros |
| 6 | `escala_remover_membro(p_funcionario uuid) returns void` | `Funcionário fora da escala` |
| 7 | `escala_adicionar_funcionario(p_setor uuid, p_nome text, p_cargo text default null, p_folgas_base smallint[] default '{}', p_chegada_padrao time default null, p_caminho smallint default null, p_posicao smallint default null) returns uuid` | **cadastra** o funcionário (mesmo insert de `funcionarios` do front: matrícula automática, `pontos_comissao` 0, sem jornada) e o põe no setor. Retorna o **id do funcionário**. `Informe o nome` + validações do nº 4 |
| 8 | `escala_aplicar_modelo_macaw(p_empresa uuid default null, p_ancora date default null) returns jsonb` | §S.7.8 |
| 9 | `escala_ajustar(p_funcionario uuid, p_data date, p_status text default null, p_chegada time default null, p_motivo text default null) returns jsonb` | define o **estado completo** do dia: `p_status` `trabalha`/`folga`/`ferias`, ou `null`/`'auto'` = automático; `p_chegada null` = padrão. Os dois nulos → apaga o ajuste. Retorna o objeto-dia (§S.8, com `funcionario_id`). `Status inválido`, `Funcionário fora da escala`, `Dia fora da escala`, `Data fora do limite` (fora de [hoje − 62, hoje + 366]), conflito de abono (§S.4) |
| 10 | `escala_ajustar_periodo(p_funcionario uuid, p_inicio date, p_fim date, p_status text, p_motivo text default null) returns int` | mesmo status em cada dia (mantém a chegada ajustada de cada dia); típico: férias. Máx. **62 dias**; dias `fora` são ignorados; retorna nº de dias gravados. Mensagens do nº 9 + `Período inválido` / `Período máximo de 62 dias` |
| 11 | `escala_trocar(p_funcionario_a uuid, p_data_a date, p_funcionario_b uuid default null, p_data_b date default null, p_motivo text default null) returns jsonb` | ver abaixo. Retorna `[objeto-dia com funcionario_id]` das células mexidas, por funcionário (A antes de B) e data |

**Troca (`escala_trocar`)** — troca os **status efetivos** (regra + ajuste), nunca as chegadas (cada um mantém a sua):
- `B` e só `data_a`: A e B trocam o status do dia `data_a` (ex.: A folgava e B trabalhava → A trabalha e B folga).
- `B`, `data_a` e `data_b`: troca A↔B em `data_a` **e** em `data_b` (o caso "A folga no X e trabalha no Y, B o inverso").
- Sem `B`, com `data_b`: A troca o próprio status entre `data_a` e `data_b` (mudar a folga de dia).
- Sem `B` e sem `data_b` → `Informe o outro funcionário ou o outro dia`; B = A → idem.
- Célula de férias → `Não é possível trocar dia de férias`; B fora da escala/outra empresa → `Funcionário fora da escala` /
  `Funcionário de outra empresa`; demais validações do nº 9.
- Gravação: status resultante igual ao automático → status `null` (volta a automático; se não houver chegada ajustada o ajuste é apagado);
  senão ajuste com o status. `motivo` padrão `Troca de folga`.

### S.7.8 `escala_aplicar_modelo_macaw` (pedido do cliente, empresa real "Macaw Camboinhas")
Idempotente; pode ser rodada numa empresa **vazia**. Passos:
1. Configuração: se não existe, cria com `p_ancora` (ou a segunda da semana atual); se existe e `p_ancora` informado, chama a regra do nº 1.
2. Setores do modelo, nesta ordem (`ordem` 1..6): **Salão, Maître, Areia, Bar, ASG, Cozinha** — reaproveita setor de mesmo nome.
3. Para cada **posição do modelo** (tabela abaixo), chave `modelo_posicao = '<setor>|<nome>'`:
   - se já há membro com essa chave na empresa → **não mexe** (o gerente pode ter renomeado/editado; rodar de novo não duplica);
   - funcionário de mesmo nome que **já está** na escala (em qualquer setor) → só marca a posição do modelo nele, sem mover;
   - senão usa o funcionário da empresa com **o mesmo nome** (sem diferença de maiúsculas/espaços nas pontas) que ainda não está na
     escala; não havendo, **cria** um funcionário provisório: `nome` = nome da posição, `cargo` = função (nome sem o número),
     `pontos_comissao = 0` (participa da comissão pelo padrão, mas com 0 ponto não recebe), sem jornada, sem admissão;
   - membro com as folgas base, caminho e posição do modelo (posição ocupada por outro → próxima livre do caminho), `ordem` = índice.
4. Reapura os funcionários envolvidos (sem efeito para os provisórios — não têm jornada).
Retorno: `{"ancora":"AAAA-MM-DD","setores":<nº de setores criados agora>,"membros":<nº de posições preenchidas agora>,
"funcionarios_criados":<nº de funcionários criados agora>}` (segunda chamada → `0, 0, 0`).

| setor | ordem: nome (folgas base) | caminhos (ordem das posições) |
|---|---|---|
| Salão | 1 Garçom 1 (QUA,QUI) · 2 Garçom 2 (QUA,QUI) · 3 Garçom 3 (QUA,QUI) · 4 Cumim 2 (QUA,DOM) · 5 Garçom 4 (SEG,TER) · 6 Garçom 5 (SEG,TER) · 7 Garçom 6 (SEG,TER) · 8 Cumim 1 (TER,DOM) | 1: Garçom 1 → Garçom 2 → Garçom 3 → Cumim 2 · 2: Garçom 4 → Garçom 5 → Garçom 6 → Cumim 1 |
| Maître | 1 Maître 1 (SEG,TER) · 2 Maître 2 (TER,QUI) · 3 Maître 3 (QUA,QUI) · 4 Gerente (QUA) · 5 Recepção (SEG,DOM) | 1: Maître 2 → Maître 1 → Recepção → Maître 3 · Gerente = folga fixa |
| Areia | 1 Areia 1 (SEG,DOM) · 2 Areia 2 (SEG,TER) · 3 Areia 3 (QUA,QUI) · 4 Areia 4 (QUA,QUI) · 5 Areia 5 (TER,SEX) | 1: Areia 2 → Areia 1 → Areia 3 → Areia 4 → Areia 5 |
| Bar | 1 Bar 1 (SEG,DOM) · 2 Bar 2 (SEG,TER) · 3 Bar 3 (QUA,QUI) · 4 Bar 4 (QUA,QUI) | 1: Bar 1 → Bar 4 → Bar 3 → Bar 2 |
| ASG | 1 ASG 1 (SEG,DOM) · 2 ASG 2 (TER,QUA) · 3 ASG 3 (QUI,SEX) | 1: ASG 1 → ASG 2 → ASG 3 |
| Cozinha | 1 Chef (QUI) · 2 Cozinha 1 (SEG,TER) · 3 Cozinha 2 (SEG,TER) · 4 Cozinha 3 (SEG,DOM) · 5 Cozinha 4 (TER,QUA) · 6 Cozinha 5 (QUA,QUI) · 7 Cozinha 6 (QUI,DOM) · 8 Cozinha 7 (QUA,SEX) | 1: Cozinha 3 → Cozinha 2 → Cozinha 1 · 2: Cozinha 4 → Cozinha 5 → Cozinha 6 → Cozinha 7 · Chef = folga fixa |

Funções (cargo): Garçom, Cumim, Maître, Gerente, Recepção, Areia, Bar, ASG, Chef, Cozinha. Total: 33 posições.

## S.8 RPCs de leitura (`[api]`, **L G A M**)

### `escala_mes(p_ano_mes text, p_empresa uuid default null) returns jsonb`
`p_ano_mes` = `'AAAA-MM'` (senão `Mês inválido (use AAAA-MM)`, 22023). Formato exato:
```json
{
  "empresa_id": "uuid", "ano_mes": "2026-11", "inicio": "2026-11-01", "fim": "2026-11-30",
  "configurada": true, "ancora": "2026-11-02", "fase": 0, "pode_editar": true, "hoje": "2026-11-13",
  "dias": [ { "data": "2026-11-01", "dia_semana": 6, "semana": -1 } ],
  "setores": [ {
      "id": "uuid", "nome": "Salão", "ordem": 1, "fase": 0,
      "caminhos": [ { "caminho": 1, "funcionarios": ["uuid", "uuid"] } ],
      "membros": [ {
          "membro_id": "uuid", "funcionario_id": "uuid", "nome": "Ana Souza", "cargo": "Garçom",
          "chegada_padrao": "17:00", "folgas_base": [0, 1], "caminho": 1, "posicao": 1, "folga_fixa": false,
          "trabalha": 22, "folgas": 8, "ferias": 0,
          "dias": [ { "data": "2026-11-01", "status": "fora", "origem": "auto", "chegada": null, "ajustado": false, "motivo": null },
                    { "data": "2026-11-02", "status": "trabalha", "origem": "auto", "chegada": "17:00", "ajustado": false, "motivo": null },
                    { "data": "2026-11-05", "status": "folga", "origem": "ajuste", "chegada": null, "ajustado": true, "motivo": "Troca com Bruno" } ]
      } ],
      "na_escala": [0, 7, 7, 4] } ],
  "na_escala": [0, 12, 12, 9]
}
```
- `dias`: um por dia do mês; `dia_semana` 0=SEG..6=DOM; `semana` = `w` da regra (null sem configuração).
- `setores` por `ordem, nome`; `membros` por `ordem, nome`; `caminhos` por número, `funcionarios` na ordem das posições.
- Cada membro tem `dias` com **um item por dia do mês** (mesma ordem de `dias`). `status` ∈ `trabalha|folga|ferias|fora`;
  `origem` = `ajuste` quando o status veio de ajuste, senão `auto`; `chegada` `'HH:MM'` só quando `trabalha` (do dia ou padrão, senão null);
  `ajustado` = existe ajuste (status ou chegada) no dia; `motivo` = do ajuste — **sempre `null` para o papel leitura**.
- `trabalha/folgas/ferias` = contagem do mês (dias `fora` não contam). `na_escala` = nº de membros com `trabalha` por dia (setor e total).
- Sem configuração: `configurada: false`, `ancora/fase/semana: null`, `setores: []` (ou os setores sem regra — todos os dias `fora`).
- `pode_editar` = `pode_operar(empresa)` (false para leitura). Leitura **vê** a escala (útil para o funcionário ver a própria folga);
  não vê `motivo` nem quem ajustou.

### `escala_semana(p_data date default null, p_empresa uuid default null) returns jsonb`
Visão "Geral"/semana base + a semana de `p_data` (padrão: dia de trabalho atual) **pela regra, sem ajustes**:
```json
{ "empresa_id": "uuid", "configurada": true, "ancora": "2026-11-02", "fase": 0,
  "semana_inicio": "2026-11-09", "semana": 1,
  "setores": [ { "id": "uuid", "nome": "Salão", "ordem": 1, "fase": 0, "total": 8,
      "caminhos": [ { "caminho": 1, "funcionarios": ["uuid"], "nomes": ["Garçom 1"] } ],
      "membros": [ { "funcionario_id": "uuid", "nome": "Garçom 1", "cargo": "Garçom", "chegada_padrao": null,
                     "caminho": 1, "posicao": 1, "folga_fixa": false, "folgas_base": [2, 3], "folgas_semana": [2, 3] } ],
      "na_escala_base": [8, 6, 4, 5, 8, 8, 6], "na_escala_semana": [8, 6, 4, 5, 8, 8, 6] } ],
  "na_escala_base": [/* 7 totais */], "na_escala_semana": [/* 7 totais */] }
```
`na_escala_base[d]` = membros sem `d` em `folgas_base`; `na_escala_semana[d]` = membros sem `d` em `folgas_semana` (índices 0=SEG..6=DOM).
Sem configuração: `semana` null e `folgas_semana = folgas_base`.

**Exportar para Excel**: no front (TSV), a partir de `escala_mes` — sem RPC.

## S.9 Mensagens novas (texto exato, 22023 salvo indicação)
`Mês inválido (use AAAA-MM)` · `A data-âncora deve ser uma segunda-feira` · `Fase inválida` · `Setor não encontrado` (P0002) ·
`Setor já existe` (23505) · `Folgas inválidas` · `Caminho inválido` · `Posição inválida` · `Posição já ocupada no caminho` (23505) ·
`Lista de membros inválida` · `Funcionário repetido na lista` · `Funcionário fora da escala` · `Dia fora da escala` ·
`Não é possível trocar dia de férias` · `Informe o outro funcionário ou o outro dia` · `Dia com férias na escala: altere pela escala`.
Reaproveitadas: `Sem permissão` (42501) · `Informe a empresa` · `Informe o nome` · `Informe a data` · `Funcionário não encontrado` (P0002) ·
`Funcionário de outra empresa` · `Status inválido` · `Data fora do limite` · `Período inválido` · `Período máximo de 62 dias` ·
`Já existe abono para o funcionário em DD/MM/AAAA`.

## S.10 Carga de demonstração (`supabase/seed/40_demo_escala.sql`, Bar Bossa Nova)
Âncora = segunda-feira da semana do dia de trabalho atual (os dias anteriores ficam `fora` e o ponto já apurado não muda).
Setores: **Salão** (caminho 1: Ana Souza SEG,TER → Bruno Lima QUA,QUI → Carla Dias SEG,DOM; chegada padrão 17:00),
**Bar** (Davi Rocha, folga fixa SEG,TER, chegada 17:30), **Cozinha** (Eva Martins, folga fixa DOM). Um ajuste demo: Bruno troca com a Ana
o primeiro dia futuro em que um folga e o outro trabalha (`escala_trocar`); Carla com férias nos 3 dias seguintes a hoje + 7. Cantina Roma: setor "Salão" com Paolo Bianchi (folga fixa SEG).

## S.11 Faltas na escala (v3)
Faltas ficam em `funcionario_faltas` (adendo extras §E.7.2 — DDL, regras, ponto e RPCs `falta_*`); a escala só **mostra** e oferece atalho.
- `escala_mes`: cada objeto-dia ganha `"falta": "justificada" | "injustificada" | null` (o `status` continua o da escala, normalmente
  `trabalha`); cada membro ganha `"faltas": <nº no mês>`. Código da célula no front/Excel: **FJ** (justificada) / **FI** (injustificada),
  no lugar de T. `na_escala` não muda (conta quem estava escalado). Leitura vê o código (sem motivo).
- Objeto-dia de `escala_ajustar`/`escala_trocar` (`escala_dia_json`) ganha `"falta"` também.
- `escala_ajustar(p_funcionario, p_data, p_status => 'falta_justificada' | 'falta_injustificada', p_motivo => …)` = `falta_registrar`
  (mesmas validações; `p_chegada` ignorado; o ajuste de status/chegada do dia não muda). Retorna o objeto-dia.
  Em `escala_ajustar_periodo` e na troca esses status → `Status inválido`.
- Qualquer **outro** `escala_ajustar`, `escala_ajustar_periodo` (dia não `fora`) ou `escala_trocar` que toque um dia com falta →
  `Dia com falta em DD/MM/AAAA: remova a falta antes` (22023). Para tirar a falta: `falta_remover(p_funcionario, p_data)`.
- Falta num dia de `folga` da escala → `Funcionário de folga na escala em DD/MM/AAAA`; em dia de férias → `Já existe abono para o
  funcionário em DD/MM/AAAA` (o abono de férias).
