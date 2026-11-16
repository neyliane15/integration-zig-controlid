# Adendo ao contrato — Control iD via RHiD (nuvem) — tipo de integração `rhid`

Complementa `docs/CONTRATO.md` (§11 integrações, §12 N8N) e convive com a importação manual do AFD (`…0300_importar_afd.sql`).
Onde houver conflito, **este adendo vale** para o tipo `rhid`.
Migração: `supabase/migrations/20261006000310_rhid.sql` (+ listas de tipo em `…0120`, aceitação do tipo em `…0230`/`…0200`).
Testes: `supabase/testes/79_rhid.sql`, `n8n/rhid/lib/rhid.test.mjs`, cenário RHiD em `n8n/integracao-real.test.mjs`.
API: `docs/referencias/rhid-swagger.json` (base `https://www.rhid.com.br/v2/api.svc`). Implantação: `docs/IMPLANTACAO-N8N-HOSTINGER.md` §4A.

## H.0 Por quê

O relógio da loja (iDClass, Portaria 671, por CPF) e o REP-P (marcações por app/web) sincronizam com o **RHiD**; o relógio não é
alcançável pela rede da loja. Em vez de túnel até o equipamento ou de baixar o AFD à mão, o N8N lê pessoas e AFD pela API do RHiD.

## H.1 Integração `rhid` (`integracoes`)

| campo | valor |
|---|---|
| `tipo` | `'rhid'` (novo valor do check; imutável como os demais) |
| segredos (`integracao_chaves_segredo`) | `email`, `senha`, `dominio` (opcional) — somente escrita, como sempre |
| parâmetros padrão (`integracao_parametros_padrao`) | `{"equipamentos": [], "incluir_rep_p": true, "dias_retroativos": 7, "importar_pessoas": true}` |
| parâmetros opcionais | `url_base` (senão variável `RHID_BASE_URL`, senão a oficial), `limite_afd` (≤ 50000), `substitui` (id do controlid_rep trocado) |
| `cursor` (só o serviço grava) | `{"nsr_por_equipamento": {"55": 1234, "99000001": 410, "c99000001": 410}, "ultimo_instante": "…"}` |
| escopos (`sync_escopo_compativel`) | `tudo`, `funcionarios`, `batidas` |
| execuções (`sync_execucoes.tipo`) | `rhid_pessoas`, `rhid_batidas` (workflow "MDG · RHiD · Importar") |
| envio ao equipamento | não existe para `rhid` (sem `parametros.envio`) |

`equipamentos` = ids do RHiD (número ou texto numérico). Vazio → todos os dispositivos `model` 1 (REP-C) e 2 (REP-A) de
`GET /device` e, com `incluir_rep_p`, o REP-P de cada `idCompany` (das pessoas e dos dispositivos): `idEquipamento = idCompany +
99000000`, pelo AFD normal **e** pelo AFD do coletor (`afd_coletor_marcacao`, chave do cursor `c<id>`). Id explícito ≥ 99000000 é
REP-P (também o coletor, se `incluir_rep_p`).

## H.2 RPCs (todas `security definer`)

| RPC | etiqueta | o que faz |
|---|---|---|
| `ingestao_rhid_pessoas(p_integracao, p_pessoas jsonb)` | `[servico]` | `PersonDTO[]` do RHiD → `controlid_usuarios` por **CPF** (o RHiD manda número: zeros à esquerda restaurados, 11 dígitos), nome, matrícula (`registration`), PIS. Pessoa sem CPF é ignorada (`sem_cpf`). Reaproveita `ingestao_controlid_usuarios` (snapshot: quem sumiu fica `removido_no_equipamento`); vínculo automático **CPF primeiro**, depois matrícula, depois PIS (só para `rhid`). Devolve o retorno da ingestão + `lidos`, `sem_cpf`. |
| `ingestao_rhid_batidas(p_integracao, p_equipamento text, p_marcacoes jsonb)` | `[servico]` | `p_equipamento` = chave do cursor (`^c?[0-9]{1,12}$`); `p_marcacoes` = saída de `lerAfd` (`{nsr, instante, cpf}`; ≤ 2000). `id_externo = "<equipamento>\|<NSR sem zeros>"`, `origem = 'controlid_rep'`, `pessoa_externa = CPF` (mesma regra do REP: vínculo do relógio, depois CPF/PIS da ficha; sem funcionário → pendente, volta ao ligar). Reaproveita `ingestao_controlid_batidas` (idempotência, apuração dos dias). Marcação com **mesmo CPF e mesmo instante** já gravada por outra fonte (AFD enviado pelo site, REP por rede, ou REP-P × coletor) conta como `duplicados` / `ja_importadas_por_outra_fonte` e não é gravada. Atualiza `cursor.nsr_por_equipamento[equip] = max(NSR)` sem regredir. Devolve o retorno da ingestão + `equipamento`, `ultimo_nsr`, `cursor`. |
| `integracao_trocar_para_rhid(p_integracao, p_nome default null) → uuid` | `[api]` (A M) | Para um `controlid_rep` (por rede ou por arquivo, `parametros.fonte = 'arquivo'`): cria a integração `rhid` (`parametros.substitui`), copia os usuários do relógio com CPF de 11 dígitos **com os vínculos** (automáticos e manuais) e desativa a antiga. Idempotente (chamar de novo devolve a mesma). As batidas antigas ficam na integração antiga e continuam no ponto. Erros: `Integração não encontrada` P0002, `Sem permissão` 42501, `Tipo de integração incompatível` 22023. |

### Migração de "arquivo" para "rhid" (mesmo REP pelos dois caminhos)

O NSR é por relógio, e as batidas por arquivo usam `id_externo = NSR` na integração "por arquivo", enquanto as do RHiD usam
`equip|NSR` na integração `rhid` — as chaves não colidem. A mesma marcação vinda pelos dois caminhos é reconhecida pelo
**CPF + instante** (o AFD 671 grava minuto e fuso; é o mesmo registro): a do RHiD é descartada como duplicada. Recomendação: trocar
com `integracao_trocar_para_rhid` e não importar mais o AFD à mão; a 1ª sincronização relê `dias_retroativos` dias (padrão 7) e
só grava o que faltava. A apuração também ignora batidas a menos de `ponto_janela_duplicada_minutos` uma da outra.

Pendência conhecida: `ponto_afd_ligar`/`ponto_afd_pendentes` (…0300, "Ligar funcionários") aceitam só `controlid_rep`; para `rhid`
o vínculo manual usa `funcionario_vincular_controlid` (aba "Pessoas do relógio" / Funcionários → vínculos).

## H.3 N8N — "MDG · RHiD · Importar" (`n8n/rhid/workflows/rhid-importar.json`, pacote `07-rhid-importar.json`)

Subfluxo (Execute Workflow Trigger), id na variável **`MDG_WF_RHID_IMPORTAR`**. Despacho (`n8n/comum/lib/supabase.mjs`):
tipo `rhid` × escopo `tudo` | `funcionarios` | `batidas` → `RHID_IMPORTAR` (fila "Sincronizar agora" e Agendador). Um nó Code com
`// @lib controlid/lib/afd.mjs` (`lerAfd`), `// @lib comum/lib/supabase.mjs` e `// @lib rhid/lib/rhid.mjs`.

1. `ingestao_integracao_config` → `POST /login {email, password, domain?}` → `accessToken` (Bearer). 401 em qualquer chamada →
   um novo login e repete; rede/408/429/5xx → 3 tentativas com espera exponencial; 4xx → erro.
2. **Pessoas** (`tudo` com `importar_pessoas`, ou `funcionarios`): execução `rhid_pessoas`; `GET /person` (lista vazia → erro, nada
   é marcado removido) → `ingestao_rhid_pessoas`.
3. **Batidas** (`tudo`, `batidas`): execução `rhid_batidas`; `GET /device` (+ `GET /person` para os `idCompany` do REP-P); para cada
   relógio: `GET /report/afd/download671` (ou `/report/afd_coletor_marcacao/download671`) com `idEquipamento`, `dataIni`,
   `dataFinal`, `nsrInicial`, `limit=50000`:
   - com cursor: `nsrInicial = cursor + 1`, janela de 90 dias terminando em hoje + 1;
   - sem cursor: `[hoje − dias_retroativos, hoje + 1]`;
   - pedido com `data_inicio`/`data_fim`: o período pedido (+ 1 dia), sem NSR (reimportação idempotente).
   O corpo (texto, ou string JSON) vai para `lerAfd`; marcações com NSR ≤ cursor são descartadas; lotes de 1000 →
   `ingestao_rhid_batidas`. Atingiu o `limit` → nova página a partir do maior NSR (até 20). Relógio automático (REP-P) com 4xx vira
   aviso; relógio explícito com erro → execução `parcial` (ou `erro` se nenhum deu certo).
4. Saída (§12.3): `{execucao_ids: [pessoas, batidas], status (pior), lidos, gravados, ignorados, erro}`.
   `detalhes` de `rhid_batidas`: por relógio `{chave, nome, rota, janela, paginas, marcacoes, gravados, duplicados, ignorados,
   sem_funcionario, ultimo_nsr, afd (resumo)}` + `avisos`. **Senha e token nunca** aparecem em log, erro ou `detalhes`.

Opcional não implementado: `GET /apuracao_ponto` (banco de horas do RHiD) — o sistema apura o próprio ponto.

## H.4 Front

Integrações → Nova integração → **Relógio de ponto (RHiD)**: e-mail, senha (somente escrita), domínio (opcional), equipamentos
(ids, opcional), dias retroativos (0–88), interruptores "Importar pessoas" e "Incluir o REP-P", com a recomendação de criar no
RHiD um usuário próprio para a integração com leitura de pessoas e relatórios. Detalhe de um `controlid_rep` ativo (A M): cartão
**Trocar para RHiD** (`integracao_trocar_para_rhid`); escolher RHiD com um REP já cadastrado mostra o atalho para a troca. Aba
"Pessoas do relógio" (vínculo manual). Rótulos: tipo "Relógio de ponto (RHiD)", execuções "RHiD · pessoas" / "RHiD · batidas".

## H.5 Mock

`n8n/mocks/rhid.mjs` (porta 54344, `iniciarMocks({ rhid: 0 })`): login (`RHID_MOCK.email`/`senha`), `/person` (CPF numérico),
`/device` (REP MACAW id 55 model 1 + iDFace model 3), AFD 671 do 55 (tipo 3) e do REP-P 99000001 (cabeçalho/empresa/empregados/
trailer da amostra real anonimizada `n8n/mocks/dados/rhid-afd-671-rep-p-amostra.txt` + tipo 7 sintéticos; o coletor devolve os
mesmos registros), validação de 90 dias e `limit`, `POST /__mock/rhid/expirar` (força 401).
