# Control iD — workflows N8N

Integração do **Meu Dia de Gerente** com os equipamentos Control iD:

| workflow (arquivo) | nome no N8N | faz |
|---|---|---|
| `workflows/controlid-importar-usuarios.json` | `MDG · Control iD · Importar usuários` | lê os usuários do equipamento → `ingestao_controlid_usuarios` (vínculo automático por matrícula/CPF/PIS) |
| `workflows/controlid-importar-batidas.json` | `MDG · Control iD · Importar batidas` | acesso: `access_logs`; REP: AFD → `ingestao_controlid_batidas` (lotes de 1000, incremental, idempotente) |
| `workflows/controlid-exportar-usuarios.json` | `MDG · Control iD · Exportar funcionários` | envio sistema → equipamento (adendo `docs/CONTRATO-ADENDO-envio-controlid.md`): cadastro, desligamento, senha, cartões, horários de acesso e foto |

Os três são **subfluxos** (gatilho *Execute Workflow Trigger*); quem os chama é o n8n-2 (`MDG · Sincronizar agora (fila)` e
`MDG · Agendador`) com a entrada do contrato §12.3. A saída é sempre
`{ execucao_ids, status: sucesso|parcial|erro, lidos, gravados, ignorados, erro }` e cada execução fica registrada em
`sync_execucoes` (`controlid_usuarios`, `controlid_batidas`, `controlid_exportar_usuarios`), inclusive quando dá erro.
**Batidas nunca são enviadas ao equipamento** (Portaria 671).

## Equipamentos suportados

| tipo da integração | modelos | API usada |
|---|---|---|
| `controlid_acesso` | iDFace, iDFace Max, iDFlex, iDAccess, iDAccess Nano | `login.fcgi`, `load_objects.fcgi` (`users`, `access_logs`, …), `create/modify/destroy_objects.fcgi`, `user_hash_password.fcgi`, `user_set_image_list.fcgi` (ou `user_set_image.fcgi`), `user_destroy_image.fcgi`, `system_information.fcgi`, `logout.fcgi` |
| `controlid_rep` | iDClass, iDClass Bio (REP-C) | `login.fcgi`, `load_users.fcgi`, `get_afd.fcgi`, `add_users.fcgi`, `update_users.fcgi`, `remove_users.fcgi`, `logout.fcgi` |

AFD lido: **Portaria 671** (registros tipo 3 e tipo 7, data-hora com fuso, CPF) e **Portaria 1510** legado (tipo 3, data/hora
local, PIS). Linhas com `\r\n`, `\n` ou `\r`, BOM e espaços no fim são aceitos; linhas corrompidas são descartadas e listadas em
`sync_execucoes.detalhes.afd.exemplos_ignoradas` (até 20). CRC-16/hash não são validados (o NSR garante a idempotência).

## 1. Cadastrar o equipamento no sistema

Tela **Integrações** → *Nova integração* (papel administrador):

1. **Tipo**: `Control iD acesso` (catraca/leitor facial) ou `Control iD REP` (relógio de ponto iDClass).
2. **Parâmetros** (visíveis):
   - acesso: `{"modelo": "iDFace", "dias_retroativos": 2, "eventos_validos": [7], "relogio_em_hora_local": true}`
   - REP: `{"modelo": "iDClass", "dias_retroativos": 2, "identificador": "cpf"}` (`"pis"` só em REP antigo da Portaria 1510)
   - envio (opcional, desligado por padrão): `"envio": {"ativo": true, "foto": true, "cartao": true, "senha": true, "horarios": true, "ao_desligar": "remover"}`
   - opcionais desta integração: `"tentativas"` (padrão 3), `"espera_segundos"` (10), `"timeout_segundos"` (30),
     `"tamanho_pagina"` (1000), `"verificar_certificado"` (false — o iDClass usa HTTPS com certificado autoassinado).
3. **Segredos** (gravados em `integracoes_segredos`, nunca aparecem no front nem nos workflows):
   `url` (ex.: `http://192.168.0.50` no acesso, `https://192.168.0.60` no REP), `login`, `senha` (usuário administrador
   do equipamento; o padrão de fábrica é `admin`/`admin` — **troque**).
4. **Sincronizar agora** → escopo *Funcionários* primeiro: confira em *Funcionários* se cada usuário do equipamento foi
   vinculado (matrícula = `registration`; no REP, CPF/PIS). Vincule à mão os que sobrarem. Depois escopo *Batidas*.

Dica: no equipamento de acesso, cadastre a **matrícula** (`registration`) igual à matrícula do funcionário no sistema; é por ela
que o vínculo automático acontece.

## 2. Rede / VPN

O N8N chama o equipamento **diretamente** (HTTP na porta 80, ou HTTPS 443 no REP). Ou seja, o N8N precisa alcançar o IP do
equipamento dentro da loja. Opções, da mais simples para a mais robusta:

1. **N8N na rede da loja** (mini-PC/Raspberry/servidor local). Só precisa de saída para a internet (Supabase). Recomendado:
   o modelo da fila "Sincronizar agora" é *pull* justamente para funcionar atrás de firewall.
2. **VPN site-a-site** ou **Tailscale/WireGuard** entre o servidor do N8N e um equipamento da loja (roteador com VPN ou um
   pequeno gateway na LAN anunciando a sub-rede do equipamento). Use o IP da LAN na `url`.
3. **Redirecionamento de porta** no roteador da loja: **evite**. Se não houver alternativa, libere só o IP do N8N, use HTTPS
   e troque a senha padrão.

Teste de alcance a partir da máquina do N8N:

```bash
curl -s -X POST http://192.168.0.50/login.fcgi -H 'Content-Type: application/json' -d '{"login":"admin","password":"SUA_SENHA"}'
# → {"session":"..."}   (no REP: curl -k https://192.168.0.60/login.fcgi ...)
```

Dê IP fixo (reserva DHCP) ao equipamento — se o IP mudar, as execuções falham com "endereço inalcançável (rede/VPN?)".

## 3. Relógio e fuso (importante)

- **Ajuste a data/hora do equipamento** (menu do equipamento ou a interface web) e, de preferência, ligue o NTP.
  A cada importação de batidas do equipamento de acesso o N8N lê `system_information.fcgi` e grava em
  `sync_execucoes.detalhes.relogio_desvio_segundos`; desvio maior que 5 min gera `aviso_relogio`.
- **Acesso — `relogio_em_hora_local`** (padrão `true`): a maioria dos equipamentos grava o `time` dos `access_logs` como a hora
  de parede local "carimbada" como UTC. Com `true` o N8N envia `instante_local` (o banco interpreta no fuso da empresa); com
  `false` envia `instante` UTC. **Valide na implantação**: bata o ponto às, por exemplo, 14:05 locais, sincronize e confira
  na tela *Ponto* se aparece 14:05. Se aparecer 11:05 ou 17:05 (diferença do fuso), inverta o parâmetro.
- **REP 671**: a data-hora do AFD já traz o fuso (`-0300`) e vai como `instante`. **REP 1510**: sem fuso, vai como `instante_local`.
- A janela de busca do acesso é `T = max(cursor.ultimo_instante − 1 dia, hoje − dias_retroativos)` no mesmo referencial do relógio.
  Se a integração ficou parada mais que `dias_retroativos` dias, recupere a lacuna com **Sincronizar agora → Batidas → período**
  (`data_inicio` ignora o cursor e o limite). No REP a busca é pelo NSR (`ultimo_nsr + 1`), então não há lacuna.

## 4. Importar os workflows no N8N

Requisitos (contrato §12.2): variáveis de ambiente do N8N `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
`N8N_BLOCK_ENV_ACCESS_IN_NODE=false`, `GENERIC_TIMEZONE=America/Sao_Paulo` (ver `n8n/.env.example`). Nenhuma credencial fica nos JSONs.

1. N8N → *Workflows* → *Import from File* → importe os três arquivos de `n8n/controlid/workflows/`.
2. Anote o id de cada um (URL do workflow) e preencha `MDG_WF_CONTROLID_USUARIOS`, `MDG_WF_CONTROLID_BATIDAS`,
   `MDG_WF_CONTROLID_EXPORTAR` no ambiente do N8N (o despachante do n8n-2 usa esses ids). Reinicie o N8N.
3. Em cada workflow: *Settings* → *Error Workflow* = `MDG · Tratador de erros`. Não precisam ficar ativos (são subfluxos).
4. Teste manual: abra `MDG · Control iD · Importar usuários`, clique no gatilho *Entrada* e use *pin data* com
   `{"integracao_id": "<id>", "empresa_id": "<id>", "escopo": "funcionarios", "gatilho": "manual"}` → *Execute workflow*.

Em ambiente de teste aponte os segredos para o mock (`npm run n8n:mocks`): acesso `http://127.0.0.1:54341`, REP
`http://127.0.0.1:54342`, `admin`/`admin`.

### Como os workflows tratam falhas
- Chamadas ao equipamento: 3 tentativas com 10 s em timeout, erro de rede, HTTP 5xx/408/429; **sessão expirada (401)** → novo
  login e repete; login recusado não é repetido. `logout.fcgi` sempre, também no erro. Mensagens em português no `erro`.
- Chamadas ao Supabase: nós HTTP com *Retry On Fail* (3×, 5 s). Falha num lote de batidas → execução `parcial` (os outros lotes
  ficam gravados; reexecutar é seguro: `on conflict do nothing`).
- Importar usuários nunca envia lista vazia (isso marcaria todos como removidos): vira `erro` sem alterar nada.
- Envio: cada item é independente; falhou um, os demais seguem e cada um recebe `enviado`/`erro` com a mensagem em
  `controlid_envios`. Tudo calcula a diferença contra o que já está no equipamento (usuário pela matrícula, cartões, regras,
  foto pelo `image_timestamp`), então reenviar não duplica nada. Horários: objetos com nome `MDG …` são recriados.

## 5. Código e testes

- `lib/controlid.mjs` — cliente com sessão/retentativa, corpos das chamadas, conversão de horário, mapeamentos, orquestração da
  importação e do envio, resumo para `ingestao_sync_finalizar`. `lib/afd.mjs` — leitor de AFD e divisão em lotes.
  Funções puras, sem `import`; o acesso à rede é injetado (`adaptadorHttpN8n(this.helpers)` no N8N).
- Os nós Code contêm uma cópia da lib (linha `// @lib controlid/lib/….mjs`, convenção de `docs/DIVISAO.md`). **Depois de editar
  uma lib rode** `node n8n/controlid/montar-workflows.mjs` (gera os três JSONs; `--conferir` só verifica).
- Testes: `node --test n8n/controlid/*.test.mjs n8n/controlid/lib/*.test.mjs` ou `npm test`.
  - `lib/afd.test.mjs`: AFD 671 e 1510 "reais" (`lib/__dados__/`), linhas corrompidas, CRLF/CR/BOM, tipo 7, NSR repetido.
  - `lib/controlid.test.mjs` e `lib/controlid-envio.test.mjs`: fuso/horário local, janela T, retentativa, sessão expirada,
    corpos, diferenças de cartões/regras, time_spans.
  - `lib/controlid.e2e.test.mjs`: as libs contra o mock do n2 (`n8n/mocks/servidor.mjs`, portas aleatórias).
  - `workflows.test.mjs`: valida os JSONs (nomes, conexões, cópias `// @lib`, nada de credencial) e **executa** os três
    workflows num mini-executor que imita o N8N (expressões, Code, IF, HTTP) contra o mock e um Supabase falso.
