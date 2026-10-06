// Chamadas ao Supabase (PostgREST) e despacho da fila "Sincronizar agora" — funções puras, sem import.
// Usada nos nós Code dos workflows (cópia marcada com `// @lib comum/lib/supabase.mjs`, conferida por `npm run n8n:verificar`).
// O transporte HTTP é injetado (`http(req) → Promise<{status, headers, corpo}>`): no N8N vem de `criarHttpN8n(this.helpers)`,
// nos testes de `criarHttpFetch(fetch)`.

export const NOMES_WORKFLOWS = {
  CONTROLID_USUARIOS: 'MDG · Control iD · Importar usuários',
  CONTROLID_BATIDAS: 'MDG · Control iD · Importar batidas',
  CONTROLID_EXPORTAR: 'MDG · Control iD · Exportar funcionários',
  ZIG_IMPORTAR: 'MDG · Zig · Importar',
  EXPORTAR_FECHAMENTO: 'MDG · Exportar fechamento CSV',
  SINCRONIZAR_AGORA: 'MDG · Sincronizar agora (fila)',
  AGENDADOR: 'MDG · Agendador',
  ROTINA_DIARIA: 'MDG · Rotina diária',
  ERROS: 'MDG · Tratador de erros',
}

/** Variável de ambiente que guarda o id (no N8N) de cada subfluxo. */
export const VARIAVEIS_SUBFLUXOS = {
  CONTROLID_USUARIOS: 'MDG_WF_CONTROLID_USUARIOS',
  CONTROLID_BATIDAS: 'MDG_WF_CONTROLID_BATIDAS',
  CONTROLID_EXPORTAR: 'MDG_WF_CONTROLID_EXPORTAR',
  ZIG_IMPORTAR: 'MDG_WF_ZIG_IMPORTAR',
  EXPORTAR_FECHAMENTO: 'MDG_WF_EXPORTAR_FECHAMENTO',
}

/** Tipo de `sync_execucoes` aberto por cada workflow (usado pelo tratador de erros). */
export const TIPO_EXECUCAO_POR_WORKFLOW = {
  'MDG · Control iD · Importar usuários': 'controlid_usuarios',
  'MDG · Control iD · Importar batidas': 'controlid_batidas',
  'MDG · Control iD · Exportar funcionários': 'controlid_exportar_usuarios',
  'MDG · Zig · Importar': 'zig_importar',
  'MDG · Exportar fechamento CSV': 'exportar_fechamento',
  'MDG · Rotina diária': 'apurar_ponto',
}

/**
 * Lê uma variável tentando cada fonte em ordem (ex.: `[() => $env, () => $vars]`). Fonte que lança erro
 * (ex.: `$env` bloqueado no N8N Cloud) é pulada. Valor vazio conta como ausente.
 */
export function lerVariavel(nome, fontes, padrao) {
  for (const fonte of fontes || []) {
    try {
      const obj = typeof fonte === 'function' ? fonte() : fonte
      const v = obj ? obj[nome] : undefined
      if (v !== undefined && v !== null && String(v).trim() !== '') return String(v).trim()
    } catch (e) {
      // fonte indisponível — tenta a próxima
    }
  }
  return padrao
}

/** Configuração do Supabase a partir das variáveis. Lança erro claro se faltar algo. */
export function configSupabase(fontes) {
  const url = lerVariavel('SUPABASE_URL', fontes)
  const chave = lerVariavel('SUPABASE_SERVICE_ROLE_KEY', fontes)
  if (!url) throw new Error('Variável SUPABASE_URL não configurada no N8N')
  if (!chave) throw new Error('Variável SUPABASE_SERVICE_ROLE_KEY não configurada no N8N')
  return { url: url.replace(/\/+$/, ''), chave }
}

export function cabecalhosSupabase(chave) {
  return { apikey: chave, Authorization: `Bearer ${chave}`, 'Content-Type': 'application/json', Accept: 'application/json' }
}

/** Monta a requisição `POST {url}/rest/v1/rpc/<nome>` com o corpo `{p_...}` (§12.2). */
export function montarChamadaRpc(cfg, nome, args, timeoutMs) {
  if (!/^[a-z_][a-z0-9_]*$/.test(nome || '')) throw new Error(`Nome de RPC inválido: ${nome}`)
  const corpo = {}
  for (const [k, v] of Object.entries(args || {})) if (v !== undefined) corpo[k] = v
  return {
    method: 'POST',
    url: `${cfg.url}/rest/v1/rpc/${nome}`,
    headers: cabecalhosSupabase(cfg.chave),
    corpo,
    timeoutMs: timeoutMs || 60000,
  }
}

/** 408, 425, 429 e 5xx valem nova tentativa; demais 4xx não. `null` (falha de rede/timeout) também vale. */
export function deveRetentar(status) {
  if (status === null || status === undefined) return true
  return status === 408 || status === 425 || status === 429 || status >= 500
}

/** Lê `Retry-After` (segundos ou data HTTP) em ms; null se ausente/inválido. */
export function lerRetryAfter(headers, agoraMs) {
  if (!headers) return null
  let v = headers['retry-after'] ?? headers['Retry-After']
  if (v === undefined || v === null || v === '') return null
  v = String(v).trim()
  if (/^\d+(\.\d+)?$/.test(v)) return Math.round(Number(v) * 1000)
  const data = Date.parse(v)
  if (Number.isNaN(data)) return null
  return Math.max(0, data - (agoraMs ?? Date.now()))
}

/** Espera antes da tentativa `n+1` (n = tentativas já feitas, ≥ 1): base × 2^(n−1), respeitando Retry-After, limitado. */
export function esperaAntesDaProxima(n, opcoes) {
  const base = opcoes?.esperaMs ?? 5000
  const max = opcoes?.maxEsperaMs ?? 60000
  const exponencial = base * Math.pow(2, Math.max(0, n - 1))
  const pedido = opcoes?.retryAfterMs
  return Math.min(max, Math.max(exponencial, pedido ?? 0))
}

export class ErroHttp extends Error {
  constructor(mensagem, detalhes) {
    super(mensagem)
    this.name = 'ErroHttp'
    this.status = detalhes?.status ?? null
    this.corpo = detalhes?.corpo
    this.tentativas = detalhes?.tentativas ?? 1
    this.url = detalhes?.url
  }
}

/** Remove segredos de uma URL antes de aparecer em mensagem de erro. */
export function urlSegura(url) {
  return String(url || '').replace(/([?&](session|token|apikey|key)=)[^&]*/gi, '$1***')
}

function resumoCorpo(corpo) {
  if (corpo === undefined || corpo === null || corpo === '') return ''
  if (typeof corpo === 'string') return corpo.slice(0, 300)
  if (typeof corpo === 'object') {
    const m = corpo.message || corpo.mensagem || corpo.error || corpo.erro || corpo.hint
    if (m) return String(m).slice(0, 300)
    try { return JSON.stringify(corpo).slice(0, 300) } catch (e) { return '' }
  }
  return String(corpo).slice(0, 300)
}

/**
 * Executa `req` com retentativa e *backoff* exponencial em falha de rede, timeout, 408/425/429/5xx.
 * opcoes: { tentativas = 3, esperaMs = 5000, maxEsperaMs = 60000, dormir(ms), rotulo }
 * Retorna `{ status, headers, corpo, tentativas }` (2xx). Lança `ErroHttp` (com `.tentativas`) se esgotar ou se 4xx.
 */
export async function requisitarComRetentativa(http, req, opcoes) {
  const tentativas = Math.max(1, opcoes?.tentativas ?? 3)
  const dormir = opcoes?.dormir || ((ms) => new Promise((ok) => setTimeout(ok, ms)))
  const rotulo = opcoes?.rotulo || `${req.method} ${urlSegura(req.url).split('?')[0]}`
  let ultimo = null
  for (let n = 1; n <= tentativas; n++) {
    let resposta = null
    let erroRede = null
    try {
      resposta = await http(req)
    } catch (e) {
      erroRede = e
    }
    if (resposta && resposta.status >= 200 && resposta.status < 300) return { ...resposta, tentativas: n }
    const status = resposta ? resposta.status : null
    ultimo = new ErroHttp(
      resposta
        ? `${rotulo}: HTTP ${status}${resumoCorpo(resposta.corpo) ? ' — ' + resumoCorpo(resposta.corpo) : ''}`
        : `${rotulo}: ${erroRede && erroRede.message ? erroRede.message : 'falha de rede'}`,
      { status, corpo: resposta ? resposta.corpo : undefined, tentativas: n, url: urlSegura(req.url) },
    )
    if (!deveRetentar(status) || n === tentativas) break
    await dormir(esperaAntesDaProxima(n, { esperaMs: opcoes?.esperaMs, maxEsperaMs: opcoes?.maxEsperaMs, retryAfterMs: resposta ? lerRetryAfter(resposta.headers) : null }))
  }
  if (tentativas > 1 && ultimo.tentativas > 1) ultimo.message += ` (após ${ultimo.tentativas} tentativas)`
  throw ultimo
}

/** Chama uma RPC (3 tentativas, 5 s de base — §12.2) e devolve o corpo já interpretado. */
export async function chamarRpc(http, cfg, nome, args, opcoes) {
  const req = montarChamadaRpc(cfg, nome, args, opcoes?.timeoutMs)
  const r = await requisitarComRetentativa(http, req, { tentativas: 3, esperaMs: 5000, rotulo: `RPC ${nome}`, ...(opcoes || {}) })
  return r.corpo === '' ? null : r.corpo
}

/** Lê linhas de uma tabela via PostgREST (service_role). `filtros` já no formato do PostgREST (ex.: {status: 'eq.executando'}). */
export async function selecionar(http, cfg, tabela, filtros, opcoes) {
  const qs = Object.entries(filtros || {}).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&')
  const req = { method: 'GET', url: `${cfg.url}/rest/v1/${tabela}${qs ? '?' + qs : ''}`, headers: cabecalhosSupabase(cfg.chave), timeoutMs: 30000 }
  const r = await requisitarComRetentativa(http, req, { tentativas: 3, esperaMs: 5000, rotulo: `GET ${tabela}`, ...(opcoes || {}) })
  return Array.isArray(r.corpo) ? r.corpo : []
}

export function mensagemDeErro(e) {
  if (!e) return 'Erro desconhecido'
  if (typeof e === 'string') return e.slice(0, 1000)
  const m = e.message || e.description || e.erro || (e.error && (e.error.message || e.error)) || String(e)
  return String(m).slice(0, 1000)
}

/** Adaptador para `this.helpers.httpRequest` do nó Code do N8N. */
export function criarHttpN8n(helpers) {
  return async (req) => {
    const r = await helpers.httpRequest({
      method: req.method,
      url: req.url,
      headers: req.headers,
      body: req.corpo,
      json: req.texto ? false : true,
      timeout: req.timeoutMs || 60000,
      returnFullResponse: true,
      ignoreHttpStatusErrors: true,
    })
    let corpo = r.body
    if (!req.texto && typeof corpo === 'string' && corpo !== '') {
      try { corpo = JSON.parse(corpo) } catch (e) { /* mantém texto */ }
    }
    return { status: r.statusCode, headers: r.headers || {}, corpo }
  }
}

/** Adaptador para `fetch` (Node ≥ 18) — testes e uso local. */
export function criarHttpFetch(fetchFn) {
  return async (req) => {
    const controle = new AbortController()
    const t = setTimeout(() => controle.abort(), req.timeoutMs || 60000)
    try {
      const r = await fetchFn(req.url, {
        method: req.method,
        headers: req.headers,
        body: req.corpo === undefined ? undefined : typeof req.corpo === 'string' ? req.corpo : JSON.stringify(req.corpo),
        signal: controle.signal,
      })
      const texto = await r.text()
      let corpo = texto
      if (!req.texto && texto !== '') {
        try { corpo = JSON.parse(texto) } catch (e) { /* mantém texto */ }
      }
      const headers = {}
      r.headers.forEach((v, k) => { headers[k.toLowerCase()] = v })
      return { status: r.status, headers, corpo }
    } catch (e) {
      if (e && e.name === 'AbortError') throw new Error(`tempo esgotado (${req.timeoutMs || 60000} ms)`)
      throw e
    } finally {
      clearTimeout(t)
    }
  }
}

// ----------------------------------------------------------------------------------------------- despacho (§12.3)

/** Subfluxos (em ordem) de uma combinação tipo × escopo. `envioAtivo` = parametros.envio.ativo do equipamento (adendo A.5). */
export function subfluxosDe(tipo, escopo, envioAtivo) {
  const controlid = tipo === 'controlid_acesso' || tipo === 'controlid_rep'
  if (escopo === 'exportar_fechamento') return ['EXPORTAR_FECHAMENTO']
  if (tipo === 'zig') return escopo === 'tudo' || escopo === 'vendas' ? ['ZIG_IMPORTAR'] : null
  if (controlid) {
    if (escopo === 'tudo') return envioAtivo ? ['CONTROLID_USUARIOS', 'CONTROLID_EXPORTAR', 'CONTROLID_BATIDAS'] : ['CONTROLID_USUARIOS', 'CONTROLID_BATIDAS']
    if (escopo === 'funcionarios') return ['CONTROLID_USUARIOS']
    if (escopo === 'batidas') return ['CONTROLID_BATIDAS']
    if (escopo === 'exportar_funcionarios') return ['CONTROLID_EXPORTAR']
  }
  return null
}

/** Item de entrada de todo subfluxo (§12.3). */
export function entradaSubfluxo(s, gatilho) {
  return {
    integracao_id: s.integracao_id ?? null,
    empresa_id: s.empresa_id ?? null,
    tipo: s.integracao_tipo ?? s.tipo ?? null,
    escopo: s.escopo ?? 'tudo',
    gatilho: gatilho || (s.solicitacao_id ? 'manual' : 'agendado'),
    solicitacao_id: s.solicitacao_id ?? null,
    data_inicio: s.data_inicio ?? null,
    data_fim: s.data_fim ?? null,
    parametros: s.parametros && typeof s.parametros === 'object' ? s.parametros : {},
  }
}

/**
 * Expande uma solicitação da fila (linha de `ingestao_sync_pegar_solicitacoes`) — ou uma integração vencida do agendador —
 * em passos ordenados. Cada passo é um item: os campos da entrada do subfluxo no topo + `_despacho` com o controle.
 * `ids` = { ZIG_IMPORTAR: '<id do workflow>', ... }. `envioAtivo` só importa para Control iD com escopo `tudo`.
 */
export function planejarDespacho(s, ids, opcoes) {
  const gatilho = opcoes?.gatilho
  const entrada = entradaSubfluxo(s, gatilho)
  const chave = s.solicitacao_id || `${entrada.integracao_id}|${entrada.escopo}`
  const base = (ordem, total, extra) => ({ ...entrada, _despacho: { chave, solicitacao_id: entrada.solicitacao_id, ordem, total, ...extra } })
  if (entrada.escopo === 'apurar_ponto') return [base(1, 1, { acao: 'apurar_ponto' })]
  if (entrada.escopo === 'exportar_fechamento' && !(entrada.parametros && entrada.parametros.fechamento_id)) {
    return [base(1, 1, { acao: 'invalido', erro: 'Solicitação de exportação sem fechamento_id' })]
  }
  const lista = subfluxosDe(entrada.tipo, entrada.escopo, opcoes?.envioAtivo === true)
  if (!lista) return [base(1, 1, { acao: 'invalido', erro: `Escopo "${entrada.escopo}" não se aplica a integração do tipo "${entrada.tipo}"` })]
  return lista.map((nome, i) => {
    const id = ids ? ids[nome] : undefined
    if (!id) return base(i + 1, lista.length, { acao: 'invalido', subfluxo: nome, erro: `Variável ${VARIAVEIS_SUBFLUXOS[nome]} não configurada no N8N (id do workflow "${NOMES_WORKFLOWS[nome]}")` })
    return base(i + 1, lista.length, { acao: 'subfluxo', subfluxo: nome, workflow_id: String(id), workflow_nome: NOMES_WORKFLOWS[nome] })
  })
}

/** Ids dos subfluxos a partir das variáveis. */
export function idsSubfluxos(fontes) {
  const ids = {}
  for (const [nome, variavel] of Object.entries(VARIAVEIS_SUBFLUXOS)) ids[nome] = lerVariavel(variavel, fontes)
  return ids
}

/** Normaliza a saída de um subfluxo (ou o erro do nó Execute Workflow) para `{status, lidos, gravados, ignorados, erro, execucao_ids}`. */
export function normalizarSaida(json) {
  const j = json || {}
  if (j.error) {
    const erro = typeof j.error === 'string' ? j.error : mensagemDeErro(j.error)
    return { status: 'erro', lidos: 0, gravados: 0, ignorados: 0, erro, execucao_ids: [] }
  }
  const status = ['sucesso', 'parcial', 'erro'].includes(j.status) ? j.status : 'erro'
  return {
    status,
    lidos: Number(j.lidos) || 0,
    gravados: Number(j.gravados) || 0,
    ignorados: Number(j.ignorados) || 0,
    erro: j.erro ?? (j.status ? null : 'Subfluxo não devolveu status'),
    execucao_ids: Array.isArray(j.execucao_ids) ? j.execucao_ids.filter(Boolean) : j.execucao_id ? [j.execucao_id] : [],
  }
}

/**
 * Junta os resultados dos passos de cada solicitação → `[{solicitacao_id, status: 'concluida'|'erro', mensagem, execucao_id}]`.
 * `passos` = [{ _despacho, resultado: saída normalizada }]. Qualquer passo `erro` → solicitação `erro`.
 */
export function consolidarSolicitacoes(passos) {
  const grupos = new Map()
  for (const p of passos) {
    const d = p._despacho || {}
    if (!d.solicitacao_id) continue
    if (!grupos.has(d.solicitacao_id)) grupos.set(d.solicitacao_id, [])
    grupos.get(d.solicitacao_id).push(p)
  }
  const saida = []
  for (const [solicitacao_id, lista] of grupos) {
    lista.sort((a, b) => (a._despacho.ordem || 0) - (b._despacho.ordem || 0))
    const resultados = lista.map((p) => p.resultado || { status: 'erro', erro: 'Sem resultado' })
    const erros = lista.filter((p, i) => resultados[i].status === 'erro')
    const parciais = resultados.filter((r) => r.status === 'parcial').length
    const tot = resultados.reduce((a, r) => ({ lidos: a.lidos + (r.lidos || 0), gravados: a.gravados + (r.gravados || 0), ignorados: a.ignorados + (r.ignorados || 0) }), { lidos: 0, gravados: 0, ignorados: 0 })
    const ids = resultados.flatMap((r) => r.execucao_ids || [])
    let mensagem
    if (erros.length) {
      mensagem = erros.map((p) => `${p._despacho.workflow_nome || p._despacho.subfluxo || p._despacho.acao}: ${p.resultado?.erro || p._despacho.erro || 'erro'}`).join(' | ')
    } else {
      mensagem = `${tot.lidos} lidos, ${tot.gravados} gravados, ${tot.ignorados} ignorados${parciais ? ` (${parciais} parcial)` : ''}`
    }
    saida.push({ solicitacao_id, status: erros.length ? 'erro' : 'concluida', mensagem: mensagem.slice(0, 1000), execucao_id: ids[ids.length - 1] || null })
  }
  return saida
}

// ----------------------------------------------------------------------------------------------- sync_execucoes

/**
 * Abre uma `sync_execucoes`, roda `trabalho(execucaoId)` e fecha com o resultado. `trabalho` devolve
 * `{status?, lidos, gravados, ignorados, detalhes?, tentativas?, erro?}`; exceção → fecha com `erro` e devolve a saída de erro.
 * Saída no formato do §12.3: `{execucao_ids, status, lidos, gravados, ignorados, erro}` (+ `retorno` do trabalho).
 */
export async function comExecucao(http, cfg, abertura, trabalho) {
  const execucaoId = await chamarRpc(http, cfg, 'ingestao_sync_iniciar', {
    p_tipo: abertura.tipo,
    p_gatilho: abertura.gatilho === 'manual' || abertura.gatilho === 'webhook' ? abertura.gatilho : 'agendado',
    p_workflow: abertura.workflow,
    p_empresa: abertura.empresa_id ?? null,
    p_integracao: abertura.integracao_id ?? null,
    p_solicitacao: abertura.solicitacao_id ?? null,
    p_periodo_inicio: abertura.periodo_inicio ?? null,
    p_periodo_fim: abertura.periodo_fim ?? null,
    p_n8n_execution_id: abertura.n8n_execution_id != null ? String(abertura.n8n_execution_id) : null,
  })
  let r
  try {
    r = (await trabalho(execucaoId)) || {}
  } catch (e) {
    r = { status: 'erro', erro: mensagemDeErro(e), tentativas: e && e.tentativas ? e.tentativas : 1 }
  }
  const status = ['sucesso', 'parcial', 'erro'].includes(r.status) ? r.status : 'sucesso'
  const saida = {
    execucao_ids: [execucaoId],
    status,
    lidos: Number(r.lidos) || 0,
    gravados: Number(r.gravados) || 0,
    ignorados: Number(r.ignorados) || 0,
    erro: status === 'sucesso' ? null : r.erro || null,
  }
  await chamarRpc(http, cfg, 'ingestao_sync_finalizar', {
    p_execucao: execucaoId,
    p_status: status,
    p_lidos: saida.lidos,
    p_gravados: saida.gravados,
    p_ignorados: saida.ignorados,
    p_erro: saida.erro,
    p_detalhes: r.detalhes || {},
    p_tentativas: Math.max(1, Number(r.tentativas) || 1),
  })
  if (r.retorno !== undefined) saida.retorno = r.retorno
  return saida
}
