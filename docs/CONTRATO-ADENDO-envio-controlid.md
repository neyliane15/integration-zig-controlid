# Adendo ao contrato — Envio de dados ao Control iD (sistema → equipamento)

Dono: **backend-1** (banco). Implementam contra este adendo: **frontend-2** (telas), **n8n-1** (workflow de envio),
**n8n-2** (despacho). Complementa `docs/CONTRATO.md`; onde houver conflito, **este adendo vale** para o envio.
Migração: `supabase/migrations/20261006000140_envio_controlid.sql` (b1). Testes: `supabase/testes/19_envio_controlid.sql` (b1).

## A.0 Resumo

O sistema passa a **alimentar** os equipamentos Control iD a partir do cadastro de funcionários:

| o quê | acesso (iDFace / iDFlex / iDAccess) | REP (iDClass) |
|---|---|---|
| cadastro (nome, matrícula, CPF/PIS) — criar/alterar | sim (`users`) | sim (`add_users`/`update_users`) |
| desligamento/inativação → remover (ou bloquear) | sim | sim (sempre remover) |
| foto facial | sim, se `envio.foto` (iDFace) | não |
| cartão/crachá | sim (`cards`) | sim (`rfid`, só o 1º cartão) |
| senha de acesso (PIN numérico) | sim (`user_hash_password` + `users.password/salt`) | sim (`password`) |
| horários de acesso | sim (`time_zones`/`time_spans`/`access_rules`/`access_rule_time_zones`/`user_access_rules`) | não |

Modelo: **estado desejado × estado enviado**. Para cada (equipamento, funcionário) existe no máximo uma linha em
`controlid_envios` com a **assinatura** (md5) do que o equipamento deveria ter. Qualquer mudança relevante muda a assinatura →
a linha volta a `pendente` com `versao + 1`. O N8N pega pendências com o *payload* pronto, envia e devolve o resultado com a
`versao` que enviou; se o cadastro mudou no meio do caminho, a linha continua `pendente` (idempotente: reenviar o mesmo payload
não causa dano). Nada é enviado a equipamento com `parametros.envio.ativo = false` (padrão: **desligado**, opt-in por equipamento).

## A.1 Parâmetros do equipamento (`integracoes.parametros`, extensão do §11.1)

```json
{
  "modelo": "iDFace",
  "envio": {
    "ativo": false,          // liga o envio para este equipamento
    "foto": true,            // padrão: true se tipo = controlid_acesso e modelo contém 'iDFace'; senão false
    "cartao": true,
    "senha": true,
    "horarios": true,        // padrão: true em controlid_acesso; sempre tratado como false em controlid_rep
    "ao_desligar": "remover" // 'remover' | 'bloquear' ('bloquear' só no acesso; no REP vale 'remover')
  }
}
```
O gatilho de `integracoes` completa as chaves ausentes de `envio` com os padrões acima (não sobrescreve as presentes).
`modelo` sugerido no front: `iDFace`, `iDFace Max`, `iDFlex`, `iDAccess`, `iDAccess Nano`, `iDClass`, `iDClass Bio` (texto livre).

## A.2 DDL

```sql
-- ================================================== funcionario_credenciais  [api:nenhum]
-- Senha de acesso (PIN). SEM acesso para anon/authenticated (RLS ligada, sem políticas, sem grants).
create table if not exists public.funcionario_credenciais (
  funcionario_id  uuid primary key references public.funcionarios (id) on delete cascade,
  empresa_id      uuid not null references public.empresas (id) on delete cascade,   -- gatilho: do funcionário
  senha           text check (senha is null or senha ~ '^[0-9]{4,8}$'),
  versao          int not null default 1,          -- +1 a cada mudança (entra na assinatura no lugar do valor)
  atualizado_em   timestamptz not null default now()
);
create index if not exists funcionario_credenciais_empresa_idx on public.funcionario_credenciais (empresa_id);

-- ======================================================= funcionario_cartoes  [api:nenhum]
create table if not exists public.funcionario_cartoes (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,   -- gatilho: do funcionário
  funcionario_id  uuid not null references public.funcionarios (id) on delete cascade,
  numero          text not null check (numero ~ '^[0-9]{1,20}$'),   -- valor decimal do cartão (como o equipamento lê)
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now(),
  unique (empresa_id, numero)
);
create index if not exists funcionario_cartoes_funcionario_idx on public.funcionario_cartoes (funcionario_id);
create index if not exists funcionario_cartoes_criado_por_idx on public.funcionario_cartoes (criado_por);
-- Número não é alterável (remover + adicionar). Cartão Wiegand: valor = área × 2^32 + código (o front PODE ajudar a calcular).

-- ========================================================= funcionario_fotos  [api:leitura]
-- A imagem fica no Supabase Storage, bucket PRIVADO 'funcionarios-fotos', caminho '<empresa_id>/<funcionario_id>/<arquivo>'.
create table if not exists public.funcionario_fotos (
  funcionario_id  uuid primary key references public.funcionarios (id) on delete cascade,
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  bucket          text not null default 'funcionarios-fotos',
  caminho         text not null,
  atualizado_por  uuid references public.perfis (id) on delete set null,
  atualizado_em   timestamptz not null default now()
);
create index if not exists funcionario_fotos_empresa_idx on public.funcionario_fotos (empresa_id);
create index if not exists funcionario_fotos_atualizado_por_idx on public.funcionario_fotos (atualizado_por);
-- RLS select: L G A da empresa. Escrita só pela RPC funcionario_definir_foto.

-- ========================================================== controlid_horarios  [api:crud]
-- "Horário de acesso": conjunto de faixas semanais em que o funcionário pode passar (só equipamentos de acesso).
create table if not exists public.controlid_horarios (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  nome           text not null check (btrim(nome) <> ''),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (empresa_id, nome)
);

create table if not exists public.controlid_horario_faixas (     -- [api:crud]
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references public.empresas (id) on delete cascade,   -- gatilho: do horário
  horario_id   uuid not null references public.controlid_horarios (id) on delete cascade,
  dia_semana   smallint not null check (dia_semana between 0 and 6),             -- 0 = domingo
  inicio       time not null,
  fim          time not null,          -- '23:59:59' = até o fim do dia; para cruzar a meia-noite use duas faixas
  constraint controlid_horario_faixas_ordem check (fim > inicio)
);
create index if not exists controlid_horario_faixas_empresa_idx on public.controlid_horario_faixas (empresa_id);
create index if not exists controlid_horario_faixas_horario_idx on public.controlid_horario_faixas (horario_id, dia_semana);

create table if not exists public.funcionario_horarios (          -- [api:crud]
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,   -- gatilho: do funcionário
  funcionario_id  uuid not null references public.funcionarios (id) on delete cascade,
  horario_id      uuid not null references public.controlid_horarios (id) on delete cascade,
  criado_em       timestamptz not null default now(),
  unique (funcionario_id, horario_id)
);
create index if not exists funcionario_horarios_empresa_idx on public.funcionario_horarios (empresa_id);
create index if not exists funcionario_horarios_horario_idx on public.funcionario_horarios (horario_id);
-- Gatilho: horário e funcionário da mesma empresa → senão 'Horário de outra empresa'.
-- Funcionário SEM horário vinculado = sem restrição nossa (vale a regra padrão do equipamento).
-- Com 1+ horários: pode passar se estiver em QUALQUER faixa de QUALQUER horário ativo vinculado.
-- RLS: select L G A; insert/update/delete G A (as três tabelas).

-- ============================================================ controlid_envios  [api:leitura]
create table if not exists public.controlid_envios (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas (id) on delete cascade,
  integracao_id      uuid not null references public.integracoes (id) on delete cascade,
  alvo               text not null check (alvo in ('funcionario', 'horarios')),
  funcionario_id     uuid references public.funcionarios (id) on delete set null,  -- null em 'horarios' e após excluir o funcionário
  funcionario_nome   text,              -- snapshot (para exibir e para remover depois de excluído)
  operacao           text not null check (operacao in ('salvar', 'remover', 'bloquear')),
  status             text not null default 'pendente'
                     check (status in ('pendente', 'enviando', 'enviado', 'erro', 'aguardando')),
  versao             int not null default 1,
  assinatura         text not null,     -- md5 do estado desejado (sem segredos: usa ids/versões)
  assinatura_enviada text,
  id_remoto          text,              -- acesso: users.id no equipamento; REP: CPF/PIS usado como chave
  mapa_remoto        jsonb not null default '{}'::jsonb,  -- 'horarios': {"<horario_id>": {"time_zone_id": n, "access_rule_id": n}}
  tentativas         int not null default 0,
  erro               text,              -- última mensagem de erro, ou motivo de 'aguardando'
  pendente_desde     timestamptz,
  pego_em            timestamptz,
  enviado_em         timestamptz,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);
create index if not exists controlid_envios_empresa_idx on public.controlid_envios (empresa_id, status);
create index if not exists controlid_envios_funcionario_idx on public.controlid_envios (funcionario_id);
create unique index if not exists controlid_envios_func_uk on public.controlid_envios (integracao_id, funcionario_id)
  where alvo = 'funcionario' and funcionario_id is not null;
create unique index if not exists controlid_envios_horarios_uk on public.controlid_envios (integracao_id)
  where alvo = 'horarios';
create index if not exists controlid_envios_fila_idx on public.controlid_envios (integracao_id, status);
-- RLS select: G A da empresa (M tudo). Escrita: só funções do banco.
```

### Significado de `status`
| status | significado |
|---|---|
| `pendente` | precisa ser enviado (estado desejado ≠ enviado) |
| `enviando` | pego pelo N8N; volta a `pendente` se ficar > 30 min sem resultado |
| `enviado` | o equipamento está igual ao desejado (`assinatura_enviada = assinatura`) |
| `erro` | última tentativa falhou (`erro`, `tentativas`); repetido automaticamente até 5 tentativas, depois só com "Reenviar" |
| `aguardando` | não dá para enviar ainda: `erro` diz o motivo (`'CPF obrigatório no REP'`, `'PIS obrigatório no REP'`, `'Aguardando envio dos horários'`) |

## A.3 Regras do estado desejado (função interna `controlid_envio_atualizar`)

Para cada integração `I` com `tipo in ('controlid_acesso','controlid_rep')`, `I.ativa`, `I.parametros.envio.ativo = true`
e empresa ativa, e cada funcionário `F` da empresa:

1. `F` **no vínculo** = `F.ativo` e `(data_admissao is null or data_admissao <= hoje)` e `(data_desligamento is null or data_desligamento >= hoje)`
   (`hoje` = `dia_de_trabalho(agora(), empresa)`).
2. `id_remoto` conhecido = o da linha de envio, senão o `user_id_externo` de `controlid_usuarios` ligado a `F` nesse equipamento
   e não `removido_no_equipamento`.
3. `F` no vínculo → `operacao = 'salvar'`. Fora do vínculo e com `id_remoto` conhecido → `operacao = envio.ao_desligar`
   (`'remover'` no REP sempre). Fora do vínculo sem `id_remoto` → não há o que fazer (linha não criada; uma pendente nunca enviada é apagada).
4. Funcionário **excluído**: as linhas com `id_remoto` viram `operacao = 'remover'`, `pendente` (o `funcionario_id` vira null; o
   snapshot `funcionario_nome`/`id_remoto` basta); as sem `id_remoto` são apagadas.
5. REP: exige CPF (`identificador = 'cpf'`, padrão) ou PIS → senão `status = 'aguardando'` com o motivo.
6. Acesso com horários: se `F` tem horários vinculados e o envio `'horarios'` do equipamento não está `enviado` →
   `aguardando` (`'Aguardando envio dos horários'`); libera sozinho quando os horários forem enviados.
   *(Revisão 2)* Ao registrar `enviado` para a linha `'horarios'`, se ficou algum funcionário `pendente` e não há pedido pendente
   da integração, `ingestao_controlid_envio_resultado` cria um `sync_solicitacoes` `exportar_funcionarios` (mensagem `Automático: …`): os
   liberados saem na próxima volta da fila (~1 min) em vez de esperar o agendador.
7. Linha `'horarios'` existe para cada equipamento de acesso com `envio.horarios = true` e ao menos um horário ativo da empresa
   (ou que já tenha `mapa_remoto` não vazio — para apagar no equipamento o que ficou sem uso).
8. A assinatura muda quando muda qualquer item do *payload* (A.5) — para senha/cartões entra a `versao` da credencial e os ids dos
   cartões, nunca os valores. Assinatura nova ≠ `assinatura` atual → `versao + 1`, `status = 'pendente'` (ou `aguardando`),
   `tentativas = 0`, `pendente_desde = agora()`. Assinatura igual à `assinatura_enviada` → `enviado` (nada a fazer).

**Quando recalcula**: gatilhos em `funcionarios` (nome, matrícula, cpf, pis, ativo, datas; insert/delete), `funcionario_credenciais`,
`funcionario_cartoes`, `funcionario_fotos`, `funcionario_horarios`, `controlid_horarios`, `controlid_horario_faixas`,
`controlid_usuarios` (vínculo) e `integracoes` (parametros/ativa); e **sempre** no início de `ingestao_controlid_envios_pendentes`
(cobre desligamentos por data, que não disparam gatilho).

## A.4 RPCs do front (`[api]`, G A M)

| assinatura | regra |
|---|---|
| `funcionario_definir_senha(p_funcionario uuid, p_senha text) returns void` | `p_senha` null/'' remove; senão só dígitos, 4 a 8 → `Senha de acesso inválida`. |
| `funcionario_adicionar_cartao(p_funcionario uuid, p_numero text) returns uuid` | remove não-dígitos; 1–20 dígitos → senão `Número de cartão inválido`; repetido na empresa → `Cartão já cadastrado` (23505). |
| `funcionario_remover_cartao(p_cartao uuid) returns void` | `Cartão não encontrado` (P0002). |
| `funcionario_definir_foto(p_funcionario uuid, p_caminho text) returns void` | `p_caminho` null remove o registro (o front apaga o arquivo no Storage). Senão tem de ser `'<empresa_id>/<funcionario_id>/<nome>.jpg|.jpeg|.png'` → senão `Foto inválida`; o objeto tem de existir no bucket → senão `Foto não encontrada`. |
| `funcionario_credenciais(p_funcionario uuid) returns jsonb` | `{"senha_definida": bool, "cartoes": [{"id": uuid, "final": "5678", "criado_em": iso}], "foto": {"caminho": text, "atualizado_em": iso} \| null}` — **nunca** a senha nem o número completo do cartão (`final` = últimos 4 dígitos). |
| `controlid_envio_reenviar(p_integracao uuid default null, p_funcionario uuid default null, p_empresa uuid default null) returns integer` | recalcula e volta a `pendente` (zera `tentativas`) as linhas `erro` (e `enviado`, se `p_funcionario` informado — "forçar reenvio") do escopo; retorna quantas. Depois o front pode chamar `sync_solicitar(p_integracao, 'exportar_funcionarios')`. |

Horários: CRUD direto nas tabelas `controlid_horarios`, `controlid_horario_faixas`, `funcionario_horarios` (RLS G A).
Situação do envio: `select` direto em `controlid_envios` (G A), ex.: por `funcionario_id`, mostrando `status`, `erro`, `enviado_em`.

**Storage** (criado pela migração quando o schema `storage` existe): bucket `funcionarios-fotos`, `public = false`, limite 2 MB,
tipos `image/jpeg`, `image/png`. Políticas em `storage.objects` para `authenticated`: `select` L G A e `insert/update/delete` G A,
quando `bucket_id = 'funcionarios-fotos'` e a 1ª pasta do caminho = id da empresa do usuário (master: qualquer).
Front: `supabase.storage.from('funcionarios-fotos').upload('<empresa>/<funcionario>/<uuid>.jpg', arquivo, { upsert: true })`,
depois `funcionario_definir_foto`. Recomendado: JPEG, rosto frontal, ≤ 1024 px no maior lado (o iDFace recusa imagens grandes demais).
Exibir: `createSignedUrl(caminho, 300)`.

## A.5 RPCs do N8N (`[servico]`)

### `ingestao_controlid_envios_pendentes(p_integracao uuid, p_limite int default 50) returns jsonb`
Valida a integração (`Integração não encontrada`, `Integração inativa`, `Tipo de integração incompatível` se não for Control iD).
Recalcula (A.3), devolve `enviando` há > 30 min a `pendente`, e pega até `p_limite` linhas `pendente` ou `erro` com
`tentativas < 5` (`for update skip locked`), passando-as a `enviando` (`pego_em = agora()`, `tentativas + 1`).
Ordem: `horarios` primeiro; depois `remover`/`bloquear`; depois `salvar`; por `pendente_desde`.
Com `envio.ativo = false` devolve `itens: []`.

```json
{
  "integracao_id": "uuid", "tipo": "controlid_acesso", "modelo": "iDFace",
  "envio": { "ativo": true, "foto": true, "cartao": true, "senha": true, "horarios": true, "ao_desligar": "remover" },
  "identificador": "cpf",
  "itens": [
    { "envio_id": "uuid", "versao": 3, "alvo": "horarios", "operacao": "salvar",
      "mapa_anterior": { "<horario_id>": { "time_zone_id": 101, "access_rule_id": 201 } },
      "horarios": [ { "horario_id": "uuid", "nome": "Salão noite",
                      "faixas": [ { "dia_semana": 6, "inicio": "16:30:00", "fim": "23:59:59",
                                    "inicio_segundos": 59400, "fim_segundos": 86399 } ] } ] },
    { "envio_id": "uuid", "versao": 1, "alvo": "funcionario", "operacao": "salvar",
      "funcionario_id": "uuid", "id_remoto": "12",
      "usuario": { "nome": "Ana Souza", "matricula": "1", "cpf": "52998224725", "pis": null },
      "senha": "1234",
      "cartoes": [ "123456789" ],
      "foto": { "bucket": "funcionarios-fotos", "caminho": "<empresa>/<func>/x.jpg", "atualizado_em": "ISO" },
      "regras_acesso": [ { "horario_id": "uuid", "access_rule_id": 201 } ] },
    { "envio_id": "uuid", "versao": 2, "alvo": "funcionario", "operacao": "remover",
      "funcionario_id": null, "id_remoto": "15", "usuario": { "nome": "Fulano", "matricula": "7", "cpf": null, "pis": null },
      "senha": null, "cartoes": [], "foto": null, "regras_acesso": [] }
  ]
}
```
- `senha`, `cartoes`, `foto`, `regras_acesso`: `null` quando o recurso está desligado em `envio` (não mexer no que existe no equipamento);
  `null`/`[]` com recurso ligado = **apagar** no equipamento (sem senha / sem cartões / sem foto / sem restrição de horário).
- `regras_acesso`: só acesso; ids remotos tirados do `mapa_remoto` dos horários já enviados.
- `id_remoto` null em `salvar` = criar o usuário. No **REP** o `id_remoto` é o CPF/PIS antigo: se diferente do atual, remover o antigo e criar o novo.
- Foto: baixar com `GET {SUPABASE_URL}/storage/v1/object/{bucket}/{caminho}` (cabeçalhos `apikey` e `Authorization: Bearer` com a
  service_role) e enviar em base64 (`user_set_image_list.fcgi`, `match: true`).
- Horários (acesso), recriação completa: apagar no equipamento os `time_zones`/`access_rules` do `mapa_anterior`, criar um `time_zone`
  por horário (nome `MDG <nome>`), um `time_span` por faixa (`start`/`end` = segundos, flag do dia `sun..sat` = 1), uma `access_rule`
  (`type` 1, nome `MDG <nome>`) + `access_rule_time_zones` + `portal_access_rules` (portal 1). Devolver o novo mapa.
- Funcionário (acesso): `users` (`name`, `registration`), senha via `user_hash_password.fcgi` → `password`/`salt`; `cards` do usuário
  substituídos pela lista; `user_access_rules` substituídos pelas `regras_acesso`. `bloquear` = manter o usuário, apagar cartões,
  senha, `user_access_rules` e definir `end_time` no passado. `remover` = `destroy_objects` do usuário.
- REP: `add_users.fcgi`/`update_users.fcgi` (`name`, `cpf`|`pis`, `registration`, `password` = senha, `rfid` = 1º cartão);
  `remove_users.fcgi` para remover.

### `ingestao_controlid_envio_resultado(p_envio uuid, p_versao int, p_status text, p_id_remoto text default null, p_erro text default null, p_mapa_remoto jsonb default null) returns jsonb`
- `p_status ∈ {'enviado','erro'}` → senão `Status inválido`. `Envio não encontrado` (P0002).
- `erro`: `status = 'erro'`, `erro = p_erro` (as tentativas já foram contadas ao pegar).
- `enviado`: grava `id_remoto` (se informado; em `remover` vira null), `mapa_remoto` (horários), `enviado_em = agora()`, `erro = null`.
  Se `p_versao = versao` → `status = 'enviado'`, `assinatura_enviada = assinatura`; senão (mudou no meio) → `pendente`.
  `salvar` no acesso com `id_remoto`: cria/atualiza `controlid_usuarios (integracao_id, user_id_externo = id_remoto)` ligado ao
  funcionário (`vinculo = 'automatico'` se não houver vínculo manual), `removido_no_equipamento = false`.
  `remover` enviado: `controlid_usuarios` correspondente fica `removido_no_equipamento = true`.
  `remover` enviado de funcionário excluído (funcionario_id null) → a linha é apagada.
- Envio `horarios` enviado → recalcula os funcionários do equipamento (os `aguardando` por horários são liberados; os com horários
  ganham `regras_acesso` novas → nova versão).
- Retorno: `{"status": "<status final>", "versao": n}`.

Execução no N8N: `sync_execucoes.tipo = 'controlid_exportar_usuarios'`. O escopo `exportar_funcionarios` passa a valer para
`controlid_acesso` **e** `controlid_rep` e executa este envio (substitui o uso de `ingestao_funcionarios_para_exportar`, que continua
existindo). Despacho sugerido (n8n-2): escopo `tudo` em Control iD = USUARIOS → ENVIAR (se `envio.ativo`) → BATIDAS.
Importar usuários **antes** de enviar evita duplicar quem já existe no equipamento (o vínculo automático por matrícula/CPF dá o `id_remoto`).

## A.6 Mensagens de erro novas (texto exato)
`Senha de acesso inválida` · `Número de cartão inválido` · `Cartão já cadastrado` · `Cartão não encontrado` · `Foto inválida` ·
`Foto não encontrada` · `Horário de outra empresa` · `Envio não encontrado` · `Status inválido`.

## A.7 Testes obrigatórios (`19_envio_controlid.sql`)
`funcionario_credenciais`/`funcionario_cartoes` sem nenhum acesso para authenticated/anon (select e escrita direta falham; nem o
master por API lê); `funcionario_credenciais()` não devolve senha nem número completo; isolamento entre empresas em todas as tabelas
novas e RPCs; ciclo pendente → enviando → enviado; mudança no meio (versão) mantém pendente; desligamento → `remover`;
exclusão → `remover` sem funcionário; REP sem CPF → `aguardando`; reexecutar o resultado (idempotência).
