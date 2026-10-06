#!/usr/bin/env node
// Gera os workflows N8N do Control iD (n8n/controlid/workflows/*.json) a partir das libs.
// Uso: `node n8n/controlid/montar-workflows.mjs` — rode sempre que mudar lib/controlid.mjs ou lib/afd.mjs, para que a
// cópia nos nós Code (linha `// @lib …`, convenção de docs/DIVISAO.md) continue idêntica à lib.
// `--conferir` não grava nada: só falha (código 1) se algum JSON estiver desatualizado.

import { readFileSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const PASTA = dirname(fileURLToPath(import.meta.url))

/** Conteúdo da lib como vai no nó Code: sem as palavras `export` (só existem no início de declarações). */
export function libSemExport(caminhoRelativoN8n) {
  const texto = readFileSync(join(PASTA, '..', caminhoRelativoN8n), 'utf8')
  return texto.replace(/^export (?=(async )?function |const |let |class )/gm, '')
}

const LIB_CONTROLID = 'controlid/lib/controlid.mjs'
const LIB_AFD = 'controlid/lib/afd.mjs'

function idDe(...partes) {
  const h = createHash('sha1').update(partes.join('|')).digest('hex')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-a${h.slice(17, 20)}-${h.slice(20, 32)}`
}

function montador(nomeWorkflow) {
  const nos = []
  const conexoes = {}
  const pos = (col, lin = 0) => [col * 240, 300 + lin * 200]

  const add = (no) => {
    no.id = idDe(nomeWorkflow, no.name)
    nos.push(no)
    return no.name
  }
  return {
    nos,
    conexoes,
    entrada: (col) => add({
      name: 'Entrada', type: 'n8n-nodes-base.executeWorkflowTrigger', typeVersion: 1.1, position: pos(col),
      parameters: { inputSource: 'passthrough' },
    }),
    rpc: (nome, rpc, corpoExpr, col, lin = 0, extra = {}) => add({
      name: nome, type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2, position: pos(col, lin),
      parameters: {
        method: 'POST',
        url: `={{ $env.SUPABASE_URL }}/rest/v1/rpc/${rpc}`,
        sendHeaders: true,
        headerParameters: {
          parameters: [
            { name: 'apikey', value: '={{ $env.SUPABASE_SERVICE_ROLE_KEY }}' },
            { name: 'Authorization', value: '=Bearer {{ $env.SUPABASE_SERVICE_ROLE_KEY }}' },
            { name: 'Content-Type', value: 'application/json' },
          ],
        },
        sendBody: true,
        specifyBody: 'json',
        jsonBody: `={{ JSON.stringify(${corpoExpr}) }}`,
        options: { timeout: 30000 },
      },
      retryOnFail: true, maxTries: 3, waitBetweenTries: 5000,
      ...extra,
    }),
    codigo: (nome, lib, trecho, col, lin = 0, notas) => add({
      name: nome, type: 'n8n-nodes-base.code', typeVersion: 2, position: pos(col, lin),
      parameters: {
        mode: 'runOnceForAllItems',
        jsCode: lib ? `// @lib ${lib}\n${libSemExport(lib)}\n// ---- uso neste nó ----\n${trecho.trim()}\n` : trecho.trim() + '\n',
      },
      ...(notas ? { notes: notas, notesInFlow: true } : {}),
    }),
    se: (nome, expr, col, lin = 0) => add({
      name: nome, type: 'n8n-nodes-base.if', typeVersion: 2.2, position: pos(col, lin),
      parameters: {
        conditions: {
          options: { caseSensitive: true, leftValue: '', typeValidation: 'loose', version: 2 },
          conditions: [{
            id: idDe(nomeWorkflow, nome, 'condicao'), leftValue: `={{ ${expr} }}`, rightValue: '',
            operator: { type: 'boolean', operation: 'true', singleValue: true },
          }],
          combinator: 'and',
        },
        looseTypeValidation: true,
        options: {},
      },
    }),
    liga: (de, para, saida = 0) => {
      conexoes[de] ??= { main: [] }
      while (conexoes[de].main.length <= saida) conexoes[de].main.push([])
      conexoes[de].main[saida].push({ node: para, type: 'main', index: 0 })
    },
  }
}

function workflow(nome, m) {
  return {
    name: nome,
    nodes: m.nos,
    connections: m.conexoes,
    active: false,
    settings: { executionOrder: 'v1', saveManualExecutions: true, callerPolicy: 'workflowsFromSameOwner', timezone: 'America/Sao_Paulo' },
    pinData: {},
    meta: { gerado_por: 'n8n/controlid/montar-workflows.mjs' },
  }
}

const ENTRADA = "$('Entrada').first().json"
const corpoIniciar = (tipo, nomeWf) => `{
  p_tipo: '${tipo}',
  p_gatilho: ['agendado', 'manual', 'webhook'].includes(${ENTRADA}.gatilho) ? ${ENTRADA}.gatilho : 'agendado',
  p_workflow: '${nomeWf}',
  p_empresa: ${ENTRADA}.empresa_id || null,
  p_integracao: ${ENTRADA}.integracao_id,
  p_solicitacao: ${ENTRADA}.solicitacao_id || null,
  p_periodo_inicio: ${ENTRADA}.data_inicio || null,
  p_periodo_fim: ${ENTRADA}.data_fim || null,
  p_n8n_execution_id: String($execution.id)
}`
const corpoConfig = `{ p_integracao: ${ENTRADA}.integracao_id }`
const CONTINUAR = { onError: 'continueRegularOutput' }

const TRECHO_CONTEXTO = `
const entrada = $('Entrada').first().json;
const execucao_id = extrairUuid($('Supabase · iniciar execução').first().json);
const config = $('Supabase · ler configuração').first().json;
const http = adaptadorHttpN8n(this.helpers, { verificarCertificado: !!(config.parametros && config.parametros.verificar_certificado) });
`
const TRECHO_SAIDA = `
// Saída padrão do subfluxo (contrato §12.3). Falha ao finalizar sync_execucoes não some: vai para "erro".
const saida = Object.assign({}, $('Resumir').first().json.saida);
const falhas = $input.all().filter((i) => i.json && i.json.error);
if (falhas.length) {
  const msg = 'Falha ao finalizar sync_execucoes: ' + JSON.stringify(falhas[0].json.error).slice(0, 300);
  saida.erro = saida.erro ? saida.erro + ' | ' + msg : msg;
}
return [{ json: saida }];
`

// --------------------------------------------------------------------------------------- importar usuários
function wfUsuarios() {
  const NOME = 'MDG · Control iD · Importar usuários'
  const m = montador(NOME)
  const a = m.entrada(0)
  const b = m.rpc('Supabase · iniciar execução', 'ingestao_sync_iniciar', corpoIniciar('controlid_usuarios', NOME), 1)
  const c = m.rpc('Supabase · ler configuração', 'ingestao_integracao_config', corpoConfig, 2, 0, CONTINUAR)
  const d = m.codigo('Control iD · buscar usuários', LIB_CONTROLID, `${TRECHO_CONTEXTO}
const busca = await buscarUsuarios({ http, config });
return [{ json: Object.assign(busca, { execucao_id, integracao_id: entrada.integracao_id }) }];`, 3, 0,
  'Login → load_objects users (acesso) ou load_users (REP) → logout. Retentativa 3×/10 s, novo login se a sessão expirar.')
  const e = m.se('Usuários lidos?', '$json.ok === true && Array.isArray($json.usuarios) && $json.usuarios.length > 0', 4)
  const f = m.rpc('Supabase · gravar usuários', 'ingestao_controlid_usuarios',
    `{ p_integracao: ${ENTRADA}.integracao_id, p_usuarios: $json.usuarios }`, 5, -1, CONTINUAR)
  const g = m.codigo('Resumir', LIB_CONTROLID, `
const busca = $('Control iD · buscar usuários').first().json;
const primeiro = $input.first().json;
const resposta = primeiro.etapa === 'equipamento' ? null : primeiro;
return resumirUsuarios({ busca, resposta }).map((json) => ({ json }));`, 6)
  const h = m.rpc('Supabase · finalizar execução', 'ingestao_sync_finalizar', '$json.finalizacao', 7, 0, CONTINUAR)
  const i = m.codigo('Saída', null, TRECHO_SAIDA, 8)
  m.liga(a, b); m.liga(b, c); m.liga(c, d); m.liga(d, e)
  m.liga(e, f, 0); m.liga(e, g, 1); m.liga(f, g); m.liga(g, h); m.liga(h, i)
  return workflow(NOME, m)
}

// ---------------------------------------------------------------------------------------- importar batidas
function wfBatidas() {
  const NOME = 'MDG · Control iD · Importar batidas'
  const m = montador(NOME)
  const a = m.entrada(0)
  const b = m.rpc('Supabase · iniciar execução', 'ingestao_sync_iniciar', corpoIniciar('controlid_batidas', NOME), 1)
  const c = m.rpc('Supabase · ler configuração', 'ingestao_integracao_config', corpoConfig, 2, 0, CONTINUAR)
  const d = m.codigo('Control iD · buscar batidas', LIB_CONTROLID, `${TRECHO_CONTEXTO}
const busca = await buscarBatidas({ http, config, entrada });
return [{ json: Object.assign(busca, { execucao_id, integracao_id: entrada.integracao_id }) }];`, 3, 0,
  'Acesso: access_logs desde T (cursor/dias_retroativos/data_inicio). REP: get_afd por NSR ou data. Logout sempre.')
  const e = m.codigo('AFD · separar lotes', LIB_AFD, `
// REP: lê o AFD (tipos 3 e 7, layouts 671 e 1510). Acesso: usa as batidas já mapeadas. Lotes de até 1000.
return separarLotes($('Control iD · buscar batidas').first().json, 1000).map((json) => ({ json }));`, 4)
  const f = m.se('Há lote para gravar?', 'Array.isArray($json.lote) && $json.lote.length > 0', 5)
  const g = m.rpc('Supabase · gravar batidas', 'ingestao_controlid_batidas',
    `{ p_integracao: ${ENTRADA}.integracao_id, p_batidas: $json.lote }`, 6, -1, CONTINUAR)
  const h = m.codigo('Resumir', LIB_CONTROLID, `
const busca = $('Control iD · buscar batidas').first().json;
const lotes = $('AFD · separar lotes').all().map((i) => i.json);
const recebidos = $input.all().map((i) => i.json);
const respostas = recebidos.length && recebidos[0].sem_lote ? [] : recebidos;
return resumirBatidas({ busca, lotes, respostas }).map((json) => ({ json }));`, 7)
  const i = m.rpc('Supabase · finalizar execução', 'ingestao_sync_finalizar', '$json.finalizacao', 8, 0, CONTINUAR)
  const j = m.codigo('Saída', null, TRECHO_SAIDA, 9)
  m.liga(a, b); m.liga(b, c); m.liga(c, d); m.liga(d, e); m.liga(e, f)
  m.liga(f, g, 0); m.liga(f, h, 1); m.liga(g, h); m.liga(h, i); m.liga(i, j)
  return workflow(NOME, m)
}

// ---------------------------------------------------------------------------- envio sistema → equipamento
function wfExportar() {
  const NOME = 'MDG · Control iD · Exportar funcionários'
  const m = montador(NOME)
  const a = m.entrada(0)
  const b = m.rpc('Supabase · iniciar execução', 'ingestao_sync_iniciar', corpoIniciar('controlid_exportar_usuarios', NOME), 1)
  const c = m.rpc('Supabase · ler configuração', 'ingestao_integracao_config', corpoConfig, 2, 0, CONTINUAR)
  const d = m.rpc('Supabase · pegar pendências de envio', 'ingestao_controlid_envios_pendentes',
    `{ p_integracao: ${ENTRADA}.integracao_id, p_limite: 100 }`, 3, 0, CONTINUAR)
  const e = m.codigo('Control iD · enviar pendências', LIB_CONTROLID, `${TRECHO_CONTEXTO}
const pendencias = $('Supabase · pegar pendências de envio').first().json;
const baixarFoto = baixadorFotoN8n(this.helpers, $env.SUPABASE_URL, $env.SUPABASE_SERVICE_ROLE_KEY);
const envio = await enviarPendencias({ http, config, pendencias, baixarFoto });
const meta = { ok: envio.ok, erro: envio.erro, tentativas: envio.tentativas, lidos: envio.lidos, detalhes: envio.detalhes, execucao_id };
return itensDeResultado(envio).map((json) => ({ json: Object.assign(json, { envio: meta }) }));`, 4, 0,
  'Adendo A.5: horários, usuários, senha, cartões, regras de acesso e foto (acesso); add/update/remove_users (REP). Um resultado por item.')
  const f = m.se('Há resultado para registrar?', '!!$json.corpo', 5)
  const g = m.rpc('Supabase · registrar resultado', 'ingestao_controlid_envio_resultado', '$json.corpo', 6, -1, CONTINUAR)
  const h = m.codigo('Resumir', LIB_CONTROLID, `
const itens = $('Control iD · enviar pendências').all().map((i) => i.json);
const envio = itens[0].envio;
const recebidos = $input.all().map((i) => i.json);
const respostas = recebidos.length && recebidos[0].sem_item ? [] : recebidos;
return resumirEnvio({ envio, itens, respostas }).map((json) => ({ json }));`, 7)
  const i = m.rpc('Supabase · finalizar execução', 'ingestao_sync_finalizar', '$json.finalizacao', 8, 0, CONTINUAR)
  const j = m.codigo('Saída', null, TRECHO_SAIDA, 9)
  m.liga(a, b); m.liga(b, c); m.liga(c, d); m.liga(d, e); m.liga(e, f)
  m.liga(f, g, 0); m.liga(f, h, 1); m.liga(g, h); m.liga(h, i); m.liga(i, j)
  return workflow(NOME, m)
}

export const WORKFLOWS = {
  'controlid-importar-usuarios.json': wfUsuarios,
  'controlid-importar-batidas.json': wfBatidas,
  'controlid-exportar-usuarios.json': wfExportar,
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const conferir = process.argv.includes('--conferir')
  let desatualizados = 0
  for (const [arquivo, gerar] of Object.entries(WORKFLOWS)) {
    const destino = join(PASTA, 'workflows', arquivo)
    const texto = JSON.stringify(gerar(), null, 2) + '\n'
    let atual = ''
    try { atual = readFileSync(destino, 'utf8') } catch { /* novo */ }
    if (atual === texto) continue
    desatualizados++
    if (conferir) console.error(`desatualizado: ${arquivo}`)
    else { writeFileSync(destino, texto); console.log(`gravado: workflows/${arquivo}`) }
  }
  if (conferir && desatualizados) process.exit(1)
  if (!desatualizados) console.log('workflows em dia')
}
