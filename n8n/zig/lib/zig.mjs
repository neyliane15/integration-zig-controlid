// Importação da Zig (contrato §8, §11.5, §12.5) — funções puras, sem import.
// Copiada no nó Code do workflow "MDG · Zig · Importar" com `// @lib zig/lib/zig.mjs` (conferida por `npm run n8n:verificar`).
// A importação recebe as dependências por parâmetro: `requisitar(req, opcoes)` (HTTP com retentativa — comum/lib/supabase.mjs)
// e `rpc(nome, args)` (chamada ao Supabase), o que a deixa testável fora do N8N.

export const ZIG_BASE_PADRAO = 'https://api.zigcore.com.br/integration'
export const ZIG_MAX_DIAS = 31
export const ZIG_PAUSA_MS = 300

/** Endpoints importados por loja × dia, na ordem de chamada, com a RPC de ingestão de cada um (§11.5). */
export const ENDPOINTS_ZIG = [
  { chave: 'saida_produtos', caminho: '/erp/saida-produtos', rpc: 'ingestao_zig_saida_produtos' },
  { chave: 'faturamento', caminho: '/erp/faturamento', rpc: 'ingestao_zig_faturamento' },
  { chave: 'compradores', caminho: '/erp/compradores', rpc: 'ingestao_zig_compradores' },
  { chave: 'faturamento_bandeiras', caminho: '/erp/faturamento/detalhesMaquinaIntegrada', rpc: 'ingestao_zig_faturamento_bandeiras' },
]

const RE_DATA = /^\d{4}-\d{2}-\d{2}$/

export function dataValida(iso) {
  if (typeof iso !== 'string' || !RE_DATA.test(iso)) return false
  const d = new Date(iso + 'T00:00:00Z')
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === iso
}

export function somarDias(iso, n) {
  const d = new Date(Date.parse(iso + 'T00:00:00Z') + n * 86400000)
  return d.toISOString().slice(0, 10)
}

/** Dias (AAAA-MM-DD) de `inicio` a `fim`, inclusive. Lança erro se inválido ou maior que `max`. */
export function diasDoPeriodo(inicio, fim, max) {
  if (!dataValida(inicio) || !dataValida(fim)) throw new Error(`Período inválido: ${inicio} a ${fim}`)
  if (fim < inicio) throw new Error(`Período inválido: ${inicio} a ${fim}`)
  const limite = max ?? ZIG_MAX_DIAS
  const dias = []
  for (let d = inicio; d <= fim; d = somarDias(d, 1)) {
    dias.push(d)
    if (dias.length > limite) throw new Error(`Período máximo de ${limite} dias`)
  }
  return dias
}

/**
 * Período a importar (§12.5): padrão `[dia_trabalho_atual − dias_retroativos, dia_trabalho_atual]`.
 * Sincronização manual com `data_inicio`/`data_fim` usa as datas pedidas (ignora `dias_retroativos`).
 * `fim` nunca passa do dia de trabalho atual; períodos com mais de 31 dias ficam com os 31 últimos (`truncado = true`).
 */
export function periodoZig(entrada, config, max) {
  const limite = max ?? ZIG_MAX_DIAS
  const hoje = config && config.dia_trabalho_atual
  if (!dataValida(hoje)) throw new Error('Configuração sem dia_trabalho_atual')
  const retro = Math.max(0, Math.min(limite - 1, Number(config.parametros && config.parametros.dias_retroativos != null ? config.parametros.dias_retroativos : 2) || 0))
  let fim = entrada && entrada.data_fim ? entrada.data_fim : hoje
  let inicio = entrada && entrada.data_inicio ? entrada.data_inicio : null
  if (!dataValida(fim)) throw new Error(`Data final inválida: ${fim}`)
  if (fim > hoje) fim = hoje
  if (inicio === null) inicio = somarDias(fim, -retro)
  if (!dataValida(inicio)) throw new Error(`Data inicial inválida: ${inicio}`)
  if (inicio > fim) throw new Error(`Período inválido: ${inicio} a ${fim}`)
  let truncado = false
  if (somarDias(inicio, limite - 1) < fim) {
    inicio = somarDias(fim, -(limite - 1))
    truncado = true
  }
  return { inicio, fim, dias: diasDoPeriodo(inicio, fim, limite), truncado }
}

/** URL completa de um endpoint da Zig. */
export function urlZig(base, caminho, params) {
  const raiz = String(base || ZIG_BASE_PADRAO).replace(/\/+$/, '')
  const qs = Object.entries(params || {})
    .filter(([, v]) => v !== undefined && v !== null && v !== '')
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
    .join('&')
  return `${raiz}${caminho}${qs ? '?' + qs : ''}`
}

/** Requisição GET da Zig: cabeçalho `Authorization: {token}` (sem "Bearer"). */
export function requisicaoZig(base, token, caminho, params, timeoutMs) {
  return { method: 'GET', url: urlZig(base, caminho, params), headers: { Authorization: token, Accept: 'application/json' }, timeoutMs: timeoutMs || 60000 }
}

/** Parâmetros de um dia para uma loja (um dia por vez: dtinicio = dtfim). */
export function paramsDia(loja, dia) {
  return { dtinicio: dia, dtfim: dia, loja }
}

/**
 * Lojas a importar: as devolvidas pela API (`[{id, name}]`), menos as marcadas `sincronizar = false` em `config.lojas`.
 * Lojas novas (ainda não em `zig_lojas`) entram (a ingestão cria com `sincronizar = true`).
 */
export function lojasParaSincronizar(lojasApi, lojasConfig) {
  const desligadas = new Set((lojasConfig || []).filter((l) => l && l.sincronizar === false).map((l) => String(l.loja_id_externo)))
  const vistas = new Set()
  const saida = []
  for (const l of lojasApi || []) {
    if (!l || l.id === undefined || l.id === null) continue
    const id = String(l.id)
    if (desligadas.has(id) || vistas.has(id)) continue
    vistas.add(id)
    saida.push(id)
  }
  return saida
}

/** Plano de chamadas (loja × dia × endpoint), na ordem em que serão feitas. */
export function planejarChamadas(lojas, dias) {
  const plano = []
  for (const loja of lojas) for (const dia of dias) for (const e of ENDPOINTS_ZIG) plano.push({ loja, dia, endpoint: e.chave, caminho: e.caminho, rpc: e.rpc })
  return plano
}

/** Converte a resposta da Zig no array repassado à RPC (a ingestão recebe o JSON da API sem transformar). */
export function itensDaResposta(corpo) {
  if (Array.isArray(corpo)) return corpo
  if (corpo === null || corpo === undefined || corpo === '') return []
  if (typeof corpo === 'object' && Array.isArray(corpo.data)) return corpo.data
  throw new Error('Resposta inesperada da Zig (esperado uma lista)')
}

export function novoResumoZig() {
  const por = {}
  for (const e of ENDPOINTS_ZIG) por[e.chave] = { chamadas: 0, lidos: 0, gravados: 0, ignorados: 0, removidos: 0, falhas: 0 }
  return { lojas: 0, dias: 0, por_endpoint: por, falhas: [], tentativas_max: 1 }
}

/** Soma o retorno de uma ingestão (`{lidos, gravados, ignorados, removidos}`) no resumo. */
export function acumularResumo(resumo, endpoint, retorno) {
  const r = resumo.por_endpoint[endpoint]
  r.chamadas += 1
  r.lidos += Number(retorno && retorno.lidos) || 0
  r.gravados += Number(retorno && retorno.gravados) || 0
  r.ignorados += Number(retorno && retorno.ignorados) || 0
  r.removidos += Number(retorno && retorno.removidos) || 0
  return resumo
}

export function registrarFalha(resumo, falha) {
  resumo.por_endpoint[falha.endpoint].chamadas += 1
  resumo.por_endpoint[falha.endpoint].falhas += 1
  if (resumo.falhas.length < 20) resumo.falhas.push(falha)
  else resumo.falhas_omitidas = (resumo.falhas_omitidas || 0) + 1
  return resumo
}

/** Resultado final: `sucesso` sem falhas; `parcial` se parte falhou; `erro` se tudo falhou. Totais somados de todos os endpoints. */
export function resumoFinalZig(resumo) {
  const tot = { lidos: 0, gravados: 0, ignorados: 0, chamadas: 0, falhas: 0 }
  for (const r of Object.values(resumo.por_endpoint)) {
    tot.lidos += r.lidos
    tot.gravados += r.gravados
    tot.ignorados += r.ignorados
    tot.chamadas += r.chamadas
    tot.falhas += r.falhas
  }
  const status = tot.falhas === 0 ? 'sucesso' : tot.falhas < tot.chamadas ? 'parcial' : 'erro'
  const erro = tot.falhas === 0 ? null
    : `${tot.falhas} de ${tot.chamadas} chamadas falharam. ` + resumo.falhas.slice(0, 3).map((f) => `${f.endpoint} ${f.loja} ${f.dia}: ${f.erro}`).join(' | ')
  const detalhes = { lojas: resumo.lojas, dias: resumo.dias, por_endpoint: resumo.por_endpoint }
  if (resumo.periodo) detalhes.periodo = resumo.periodo
  if (resumo.falhas.length) detalhes.falhas = resumo.falhas
  if (resumo.falhas_omitidas) detalhes.falhas_omitidas = resumo.falhas_omitidas
  if (resumo.aviso) detalhes.aviso = resumo.aviso
  return { status, lidos: tot.lidos, gravados: tot.gravados, ignorados: tot.ignorados, erro: erro ? erro.slice(0, 1000) : null, detalhes, tentativas: resumo.tentativas_max }
}

/**
 * Importa a Zig de uma integração (§12.5). Não abre/fecha `sync_execucoes` (quem chama faz isso).
 * deps: {
 *   requisitar(req, opcoes) → Promise<{status, corpo, tentativas}>   (lança com `.tentativas` ao esgotar)
 *   rpc(nome, args) → Promise<corpo>
 *   dormir(ms), baseUrl, pausaMs = 300, tentativas = 3, esperaMs = 10000, timeoutMs = 60000
 * }
 * Retorna `{status, lidos, gravados, ignorados, erro, detalhes, tentativas}` (formato de `ingestao_sync_finalizar`).
 * Falha ao listar/gravar lojas → lança (a execução inteira é `erro`). Falha num (loja, dia, endpoint) → segue e vira `parcial`.
 */
export async function importarZig(config, entrada, deps) {
  if (!config || config.tipo !== 'zig') throw new Error('Tipo de integração incompatível')
  const token = config.segredos && config.segredos.token
  if (!token) throw new Error('Token da Zig não configurado (Integrações → Zig → segredos)')
  const rede = config.parametros && config.parametros.rede
  if (!rede) throw new Error('Parâmetro "rede" da Zig não configurado')
  const base = deps.baseUrl || ZIG_BASE_PADRAO
  const opcoesHttp = { tentativas: deps.tentativas ?? 3, esperaMs: deps.esperaMs ?? 10000, dormir: deps.dormir }
  const pausa = deps.pausaMs ?? ZIG_PAUSA_MS
  const dormir = deps.dormir || ((ms) => new Promise((ok) => setTimeout(ok, ms)))
  const periodo = periodoZig(entrada, config)
  const resumo = novoResumoZig()
  resumo.periodo = { inicio: periodo.inicio, fim: periodo.fim, truncado: periodo.truncado }

  const rLojas = await deps.requisitar(requisicaoZig(base, token, '/erp/lojas', { rede }, deps.timeoutMs), { ...opcoesHttp, rotulo: 'Zig /erp/lojas' })
  resumo.tentativas_max = Math.max(resumo.tentativas_max, rLojas.tentativas || 1)
  const lojasApi = itensDaResposta(rLojas.corpo)
  await deps.rpc('ingestao_zig_lojas', { p_integracao: config.integracao_id, p_lojas: lojasApi })
  const lojas = lojasParaSincronizar(lojasApi, config.lojas)
  resumo.lojas = lojas.length
  resumo.dias = periodo.dias.length
  if (!lojas.length) {
    resumo.aviso = lojasApi.length ? 'Nenhuma loja marcada para sincronizar' : `A Zig não devolveu lojas para a rede ${rede}`
    return resumoFinalZig(resumo)
  }

  let primeira = true
  for (const c of planejarChamadas(lojas, periodo.dias)) {
    if (!primeira && pausa > 0) await dormir(pausa)
    primeira = false
    let etapa = 'zig'
    try {
      const r = await deps.requisitar(requisicaoZig(base, token, c.caminho, paramsDia(c.loja, c.dia), deps.timeoutMs), { ...opcoesHttp, rotulo: `Zig ${c.caminho}` })
      resumo.tentativas_max = Math.max(resumo.tentativas_max, r.tentativas || 1)
      const itens = itensDaResposta(r.corpo)
      etapa = 'supabase'
      const retorno = await deps.rpc(c.rpc, { p_integracao: config.integracao_id, p_loja: c.loja, p_data: c.dia, p_itens: itens })
      acumularResumo(resumo, c.endpoint, retorno)
    } catch (e) {
      if (e && e.tentativas) resumo.tentativas_max = Math.max(resumo.tentativas_max, e.tentativas)
      registrarFalha(resumo, { loja: c.loja, dia: c.dia, endpoint: c.endpoint, etapa, status: e && e.status ? e.status : null, erro: String((e && e.message) || e).slice(0, 300) })
    }
  }
  return resumoFinalZig(resumo)
}

/**
 * Lê um endpoint paginado da Zig (`/erp/invoice`, `/erp/checkins`) juntando todas as páginas.
 * Aceita resposta `{data, page, totalPages|hasNextPage}` ou lista simples (para quando vier vazia ou menor que `pageSize`).
 */
export async function lerPaginadoZig(requisitar, base, token, caminho, params, opcoes) {
  const pageSize = opcoes?.pageSize ?? 100
  const maxPaginas = opcoes?.maxPaginas ?? 200
  const todos = []
  for (let page = 1; page <= maxPaginas; page++) {
    const r = await requisitar(requisicaoZig(base, token, caminho, { ...params, page, pageSize }, opcoes?.timeoutMs), opcoes?.http)
    const corpo = r.corpo
    const itens = itensDaResposta(corpo)
    todos.push(...itens)
    if (Array.isArray(corpo)) {
      if (itens.length < pageSize) return todos
      continue
    }
    const total = Number(corpo.totalPages || corpo.lastPage || 0)
    const temMais = corpo.hasNextPage === true || (total > 0 && page < total)
    if (!temMais || !itens.length) return todos
  }
  throw new Error(`Paginação de ${caminho} passou de ${maxPaginas} páginas`)
}
