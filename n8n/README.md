# N8N — Meu Dia de Gerente

O N8N é o "braço" do sistema que fala com a **Zig** (vendas) e com os equipamentos **Control iD** (ponto/acesso) e grava tudo no
Supabase por RPCs de ingestão idempotentes (`ingestao_*`, contrato §10–§12). O front nunca fala com Zig/Control iD nem com o N8N:
o botão "Sincronizar agora" só grava um pedido em `sync_solicitacoes`, que o N8N busca a cada minuto.

```
n8n/
├─ README.md, .env.example, verificar.mjs
├─ zig/       workflows/zig-importar.json            lib/zig.mjs (+ teste)
├─ comum/     workflows/sincronizar-agora.json, agendador.json, rotina-diaria.json, exportar-fechamento.json, erros.json
│             lib/supabase.mjs, lib/csv.mjs (+ testes), workflows.test.mjs
├─ controlid/ workflows/controlid-*.json, lib/afd.mjs, lib/controlid.mjs  (ver controlid/README.md)
└─ mocks/     servidor.mjs (Zig 54340, Control iD acesso 54341, REP 54342), dados/, supabase-falso.mjs, simulador-n8n.mjs
```

## 1. Instalar o N8N

**Recomendado: self-hosted na rede da loja** (ou com VPN até ela). O N8N precisa alcançar o IP do equipamento Control iD
(`http://192.168.x.x`), o que um N8N na nuvem não consegue sem VPN/redirecionamento de porta.

Docker (exemplo mínimo):

```bash
docker volume create n8n_dados
docker run -d --name n8n --restart unless-stopped -p 5678:5678 \
  --env-file /caminho/seguro/n8n.env \
  -v n8n_dados:/home/node/.n8n docker.n8n.io/n8nio/n8n
```

`n8n.env` = cópia preenchida de [`n8n/.env.example`](.env.example) (fora do repositório). Sem Docker: `npx n8n` com as mesmas
variáveis no ambiente. Abra `http://<máquina>:5678` e crie o usuário dono.

**N8N Cloud**: funciona para a Zig, mas: (1) o Cloud bloqueia `$env` — os nós Code do n8n-2 leem `$env` e, na falta, `$vars`
(Settings → Variables, planos que têm Variables); os workflows do Control iD usam `$env` em nós HTTP e precisam de self-hosted;
(2) o Control iD só é alcançável com VPN/porta exposta. Por isso, prefira self-hosted.

## 2. Variáveis

| variável | para quê |
|---|---|
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | acesso do N8N ao banco (ver §3) |
| `MDG_WF_CONTROLID_USUARIOS`, `MDG_WF_CONTROLID_BATIDAS`, `MDG_WF_CONTROLID_EXPORTAR`, `MDG_WF_ZIG_IMPORTAR`, `MDG_WF_EXPORTAR_FECHAMENTO` | ids dos subfluxos no seu N8N (preencha **depois** de importar, §4) |
| `ZIG_BASE_URL` | padrão `https://api.zigcore.com.br/integration`; testes: `http://127.0.0.1:54340/integration` |
| `MDG_EMAIL_RELATORIOS`, `MDG_EMAIL_REMETENTE` | destino/remetente do CSV de comissão e dos avisos de erro |
| `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` | **obrigatório** — sem isso os nós não leem as variáveis |
| `GENERIC_TIMEZONE=America/Sao_Paulo`, `TZ` | a Rotina diária roda às 05:30 neste fuso |
| `N8N_RUNNERS_TASK_TIMEOUT=900` | a importação da Zig roda minutos num nó Code (o padrão de 60 s é pouco) |

O token da Zig e a URL/usuário/senha dos equipamentos **não** são variáveis do N8N: ficam em `integracoes_segredos` (cadastrados
pela tela Integrações) e o N8N os lê por `ingestao_integracao_config`. Mudou a variável? Reinicie o N8N.

## 3. Credencial do Supabase (service_role)

O N8N usa a chave **service_role** (Supabase → Project Settings → API → `service_role` / *secret key*). Ela ignora a RLS e só
executa as RPCs `[servico]`; **nunca** a coloque no front, no repositório ou em um nó (o `verificar.mjs` acusa chave fixa).
Os workflows a recebem por `SUPABASE_SERVICE_ROLE_KEY` e mandam `apikey` + `Authorization: Bearer` em cada chamada
(`POST {SUPABASE_URL}/rest/v1/rpc/<rpc>`). Não é preciso criar credencial do tipo Supabase no N8N.

Ambiente local (`npm run local`, `ferramentas/local/`): use `SUPABASE_URL=http://127.0.0.1:54321` e a service_role que o
`subir.sh` imprime.

**SMTP**: os nós "Enviar e-mail" (Exportar fechamento) e "Avisar por e-mail" (Tratador de erros) precisam de uma credencial
SMTP — abra cada nó após importar e escolha/crie a credencial.

## 4. Importar os workflows (ordem)

Em *Workflows → Import from File*, importe nesta ordem e anote o id de cada um (está na URL `/workflow/<id>`):

| # | arquivo | nome | gatilho | ativar? |
|---|---|---|---|---|
| 1 | `comum/workflows/erros.json` | MDG · Tratador de erros | Error Trigger | não precisa (é chamado pelo N8N) |
| 2 | `controlid/workflows/controlid-importar-usuarios.json` | MDG · Control iD · Importar usuários | subfluxo | não |
| 3 | `controlid/workflows/controlid-importar-batidas.json` | MDG · Control iD · Importar batidas | subfluxo | não |
| 4 | `controlid/workflows/controlid-exportar-usuarios.json` | MDG · Control iD · Exportar funcionários | subfluxo | não |
| 5 | `zig/workflows/zig-importar.json` | MDG · Zig · Importar | subfluxo | não |
| 6 | `comum/workflows/exportar-fechamento.json` | MDG · Exportar fechamento CSV | subfluxo | não |
| 7 | `comum/workflows/sincronizar-agora.json` | MDG · Sincronizar agora (fila) | a cada 1 min | **sim** |
| 8 | `comum/workflows/agendador.json` | MDG · Agendador | a cada 15 min | **sim** |
| 9 | `comum/workflows/rotina-diaria.json` | MDG · Rotina diária | 05:30 | **sim** |

Depois:
1. Preencha `MDG_WF_*` com os ids de 2–6 e reinicie o N8N.
2. Em **cada** workflow: *Settings → Error workflow* = "MDG · Tratador de erros"; *Timezone* = America/Sao_Paulo (já vem no JSON).
3. Configure a credencial SMTP nos dois nós de e-mail.
4. Teste manualmente (botão *Test workflow*): primeiro "Sincronizar agora (fila)" com um pedido feito pelo front.
5. Ative **na ordem 7 → 8 → 9** (fila primeiro, para atender os pedidos do front; depois o agendador; por último a rotina).

## 5. O que cada workflow faz

- **Sincronizar agora (fila)** — a cada minuto `ingestao_sync_pegar_solicitacoes(5)` e despacha (contrato §12.3 + adendo de envio):

  | tipo \ escopo | `tudo` | `funcionarios` | `batidas` | `vendas` | `exportar_funcionarios` |
  |---|---|---|---|---|---|
  | `controlid_acesso` / `controlid_rep` | Usuários → Exportar (só se `parametros.envio.ativo`) → Batidas | Usuários | Batidas | — | Exportar |
  | `zig` | Zig · Importar | — | — | Zig · Importar | — |

  `apurar_ponto` chama `ingestao_apurar_ponto(p_empresa, p_inicio, p_fim)` direto (com `sync_execucoes` própria);
  `exportar_fechamento` chama o subfluxo de exportação. `data_inicio`/`data_fim` do pedido vão para o subfluxo (pedido manual com
  datas ignora `dias_retroativos`). Ao fim, `ingestao_sync_concluir_solicitacao` (`concluida`, ou `erro` se algum passo falhou).
  Escopo incompatível ou variável `MDG_WF_*` faltando → pedido em `erro` com a explicação (e uma `sync_execucoes` de erro, visível
  na tela de Integrações).
- **Agendador** — a cada 15 min `ingestao_integracoes_ativas(p_somente_vencidas = true)` e roda o subfluxo de cada integração
  vencida com escopo `tudo`, gatilho `agendado`.
- **Rotina diária** — 05:30: `ingestao_apurar_ponto()` (todas as empresas, últimos 3 dias) e `ingestao_tarefas_gerar()`, cada um
  com sua `sync_execucoes` global.
- **Zig · Importar** — `GET /erp/lojas?rede=` → `ingestao_zig_lojas`; para cada loja com `sincronizar` e cada dia do período
  (padrão `[hoje − dias_retroativos, hoje]`, máx. 31, **um dia por vez**): `saida-produtos`, `faturamento`, `compradores`,
  `faturamento/detalhesMaquinaIntegrada` → `ingestao_zig_*`, que **substituem o dia** (reimportar = mesmo resultado). Cabeçalho
  `Authorization: {token}`; pausa de 300 ms entre chamadas; timeout de 60 s; retentativa com *backoff* exponencial em falha de
  rede/timeout/408/429/5xx (3 tentativas, 10 s → 20 s, respeitando `Retry-After`). Uma `sync_execucoes` `zig_importar` com
  `detalhes = {lojas, dias, periodo, por_endpoint: {saida_produtos: {chamadas, lidos, gravados, ignorados, removidos, falhas}, …}, falhas}`;
  falha em parte das chamadas → `parcial`; em todas → `erro`.
- **Exportar fechamento CSV** — `ingestao_fechamento_exportar` → CSV de comissão (§13, idêntico ao do front: UTF-8 com BOM, `;`,
  `\r\n`, nome `comissao_<empresa>_<inicio>_<fim>.csv`) → e-mail para `MDG_EMAIL_RELATORIOS`.
- **Tratador de erros** — para qualquer workflow que quebre: fecha como `erro` as `sync_execucoes` que ficaram "executando" naquela
  execução (busca por `n8n_execution_id`) e, se houver `MDG_EMAIL_RELATORIOS`, avisa por e-mail. Pedidos da fila que ficarem
  presos expiram sozinhos em 30 min (`sync_solicitar`/`ingestao_sync_iniciar`).

Chamadas ao Supabase: nos workflows do n8n-2 são feitas dentro dos nós Code (lib `comum/lib/supabase.mjs`, com os mesmos cabeçalhos
e a política do §12.2: 3 tentativas, 5 s de base) — assim o *backoff*, o `Retry-After` e respostas escalares (uuid, inteiro, void)
são tratados de forma uniforme.

## 6. Código dos nós Code (`// @lib`)

A fonte de verdade é `n8n/**/lib/*.mjs` (funções puras, sem `import`). Cada nó Code começa com `// @lib <caminho>` + o conteúdo da
lib **sem** `export` (pode haver várias libs em sequência) e depois o trecho de uso. Mudou uma lib?

```bash
node n8n/verificar.mjs --atualizar   # reescreve as cópias em zig/ e comum/ (as de controlid/ são do n8n-1)
npm run n8n:verificar                 # confere tudo
```

No N8N, depois de editar um workflow pela interface, exporte (*Download*) por cima do JSON e rode o verificador.

## 7. Testes

```bash
node --test "n8n/**/*.test.mjs"   # ou: npm test (vitest roda os mesmos arquivos e compara o CSV com web/src/lib/csv.ts)
npm run n8n:verificar
npm run n8n:mocks                 # sobe os mocks para testar com um N8N de verdade
```

- `zig/lib/zig.test.mjs`, `comum/lib/*.test.mjs`: libs puras + ponta a ponta (HTTP real) contra o mock da Zig e um Supabase falso
  (`mocks/supabase-falso.mjs`), inclusive 429 com `Retry-After`, 500 permanente, token inválido, paginação e reimportação idêntica.
- `comum/workflows.test.mjs`: executa os **JSON dos workflows** (código real dos nós Code) num simulador mínimo
  (`mocks/simulador-n8n.mjs`): fila com 5 pedidos de tipos diferentes, agendador, rotina diária, exportação (com falha de SMTP) e
  tratador de erros. O simulador não substitui importar no N8N — ele pega erro de código e de fiação.
- `mocks/servidor.test.mjs`: comportamento dos mocks.

### Mocks (`node n8n/mocks/servidor.mjs`)

| porta | imita | credenciais | destaques |
|---|---|---|---|
| 54340 | Zig `/integration/erp/...` | `Authorization: token-mock` | `rede-mock` → `loja-1` "Bossa Nova Salão"; vendas determinísticas por data (garçons Ana Souza, Bruno Lima, Davi Rocha; `Tip` = 10%; formas Crédito/Débito/Pix/Dinheiro; faturamento = Σ itens + serviço); `rede-erro` → `loja-500` (sempre 500) e `loja-429` (sempre 429, `Retry-After: 1`); `/erp/invoice` e `/erp/checkins` paginados (`page`, `pageSize` → `{data, page, totalPages, hasNextPage}`) |
| 54341 | Control iD acesso | `admin`/`admin` → `sessao-mock` | users 1–5 (matrículas 1–5); `access_logs` evento 7 nos horários das escalas dos últimos 7 dias (sem a volta do intervalo da Carla anteontem); `create/modify/destroy/load/count_objects` com estado em memória (users, cards, time_zones, time_spans, access_rules, user_access_rules…), `user_set_image`, `user_set_image_list`, `user_hash_password` |
| 54342 | Control iD REP (iDClass) | `admin`/`admin` → `sessao-rep-mock` | `load_users` (CPFs dos demo), `add/update/remove_users`, `get_afd` (Portaria 671, `initial_nsr`/`initial_date`) |

Controle: `GET /__estado` (o que foi gravado), `POST /__mock/reset`, `POST /__mock/falhas {"caminho","status","vezes"}`,
`GET /__mock/chamadas`. Erro simulável: texto com `#ERRO` em create/modify/add/update → 400. `MOCK_AGORA=2026-10-06T12:00:00-03:00`
fixa o relógio. Para usar com um N8N local: `ZIG_BASE_URL=http://127.0.0.1:54340/integration` e, na carga demo, as integrações já
apontam para `http://127.0.0.1:54341` / `:54342` com token `token-mock`.

## 8. Problemas comuns

| sintoma | causa provável |
|---|---|
| `Variável SUPABASE_URL não configurada` / `access to env vars denied` | falta `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` ou a variável |
| pedido do front fica "Na fila" | "Sincronizar agora (fila)" desativado, ou N8N parado |
| pedido em erro `Variável MDG_WF_… não configurada` | preencha o id do subfluxo e reinicie |
| `RPC …: HTTP 401` | service_role errada; `HTTP 404 … Could not find the function` → banco sem as migrações |
| Zig `HTTP 401` | token da integração errado (Integrações → Zig → segredos) |
| Zig `parcial` com `HTTP 429` | limite da Zig; o próximo ciclo reimporta os dias (é idempotente) |
| `Task request timed out` no nó "Importar Zig" | aumente `N8N_RUNNERS_TASK_TIMEOUT` |
