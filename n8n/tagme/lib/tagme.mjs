// Importação de reservas da Tagme (adendo extras/ocorrências/reservas) — funções puras, sem import.
// Copiada no nó Code do workflow "MDG · Tagme · Importar" com `// @lib tagme/lib/tagme.mjs` (conferida por `npm run n8n:verificar`).
//
// A Tagme NÃO tem API pública (só para parceiros, sob contrato). Por isso nada aqui assume endpoint ou nome de campo:
// tudo vem da integração tipo 'tagme' (tela Integrações):
//
//   segredos   { token?, cookie?, url? }                         ← nunca nos parâmetros (que o front lê)
//   parametros {
//     base_url:  'https://waitlist.tagme.com.br'                  (exemplo; ou segredos.url; ou variável TAGME_BASE_URL)
//     caminho:   '/api/...'                                       (obrigatório: o endpoint que devolve a lista de reservas)
//     metodo:    'GET' | 'POST'                                   (padrão GET; em POST os parâmetros vão no corpo JSON)
//     autenticacao: { cabecalho: 'Authorization', prefixo: 'Bearer' }   (o valor vem de segredos.token; prefixo '' = só o token)
//                   segredos.cookie (se houver) vai no cabeçalho Cookie
//     consulta: { modo: 'periodo' | 'dia', param_inicio: 'start_date', param_fim: 'end_date', param_dia: 'date',
//                 formato_data: 'AAAA-MM-DD' | 'DD/MM/AAAA' | 'AAAAMMDD' | 'iso' | 'epoch' | 'epoch_ms', extras: {...} }
//     paginacao: { param_pagina: 'page', inicio: 1, param_tamanho: 'per_page', tamanho: 100, max_paginas: 50,
//                  caminho_total_paginas: 'meta.total_pages' }   (opcional; sem `param_pagina` = uma chamada só)
//     mapeamento: { lista: 'data.reservations', id: 'id', data: 'date', hora: 'time', data_hora: 'datetime', nome: 'customer.name',
//                   telefone, email, pessoas, status, observacao, mesa, status_map: { 'seated': 'sentada', ... } }
//                 cada campo aceita um caminho ("a.b.0.c") ou uma lista de caminhos (o 1º preenchido vence);
//                 o que não for informado usa MAPEAMENTO_PADRAO_TAGME (nomes comuns em inglês e português).
//     dias_retroativos: 1, dias_futuros: 30                      (período padrão: [hoje − retro, hoje + futuros], máx. 62 dias)
//   }
//
// Quando a Tagme liberar a API de parceiro (ou se descobrir o endpoint interno do painel), basta preencher
// base_url/caminho/autenticacao/consulta/mapeamento — sem mexer neste código. Ver docs/IMPLANTACAO-N8N-HOSTINGER.md §6.

export const TAGME_BASE_EXEMPLO = 'https://waitlist.tagme.com.br'
export const TAGME_MAX_DIAS = 62
export const TAGME_STATUS = ['confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu']

/** Nomes de campo tentados quando `parametros.mapeamento` não diz nada (o 1º preenchido vence). */
export const MAPEAMENTO_PADRAO_TAGME = {
  lista: ['data.reservations', 'reservations', 'data.items', 'items', 'data.results', 'results', 'data', 'reservas'],
  id: ['id', '_id', 'reservation_id', 'reservationId', 'uuid', 'code', 'codigo'],
  data: ['date', 'reservation_date', 'reservationDate', 'data', 'day'],
  hora: ['time', 'hour', 'reservation_time', 'reservationTime', 'hora', 'horario'],
  data_hora: ['datetime', 'date_time', 'dateTime', 'scheduled_at', 'scheduledAt', 'start', 'starts_at', 'startsAt', 'data_hora'],
  nome: ['customer.name', 'client.name', 'guest.name', 'user.name', 'customer_name', 'customerName', 'name', 'nome', 'cliente.nome'],
  telefone: ['customer.phone', 'client.phone', 'guest.phone', 'user.phone', 'phone', 'customer_phone', 'telefone', 'celular', 'cliente.telefone'],
  email: ['customer.email', 'client.email', 'guest.email', 'user.email', 'email', 'customer_email', 'cliente.email'],
  pessoas: ['party_size', 'partySize', 'people', 'guests', 'pax', 'covers', 'seats', 'pessoas', 'quantidade_pessoas'],
  status: ['status', 'state', 'situacao'],
  observacao: ['notes', 'note', 'observation', 'observations', 'comments', 'comment', 'observacao', 'obs'],
  mesa: ['table.name', 'table', 'table_name', 'tableName', 'mesa'],
}

/** Tradução de status (minúsculas, sem acento) → status do sistema. `status_map` da integração complementa/sobrepõe. */
export const STATUS_PADRAO_TAGME = {
  confirmed: 'confirmada', confirmada: 'confirmada', confirmado: 'confirmada', accepted: 'confirmada', booked: 'confirmada', approved: 'confirmada',
  pending: 'pendente', pendente: 'pendente', waiting: 'pendente', aguardando: 'pendente', requested: 'pendente', new: 'pendente', created: 'pendente',
  canceled: 'cancelada', cancelled: 'cancelada', cancelada: 'cancelada', cancelado: 'cancelada', rejected: 'cancelada', recusada: 'cancelada', declined: 'cancelada',
  seated: 'sentada', sentada: 'sentada', sentado: 'sentada', checked_in: 'sentada', checkin: 'sentada', arrived: 'sentada', present: 'sentada',
  finished: 'concluida', completed: 'concluida', concluida: 'concluida', concluido: 'concluida', done: 'concluida', closed: 'concluida', left: 'concluida',
  no_show: 'nao_compareceu', noshow: 'nao_compareceu', 'no-show': 'nao_compareceu', nao_compareceu: 'nao_compareceu', absent: 'nao_compareceu', missed: 'nao_compareceu',
}

const RE_DATA = /^\d{4}-\d{2}-\d{2}$/
const OFFSET_SP_MIN = -180 // America/Sao_Paulo (sem horário de verão desde 2019)

export function dataValidaTagme(iso) {
  if (typeof iso !== 'string' || !RE_DATA.test(iso)) return false
  const d = new Date(iso + 'T00:00:00Z')
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === iso
}

export function somarDiasTagme(iso, n) {
  return new Date(Date.parse(iso + 'T00:00:00Z') + n * 86400000).toISOString().slice(0, 10)
}

function inteiroEntre(v, padrao, min, max) {
  const n = v === undefined || v === null || v === '' ? padrao : Math.trunc(Number(v))
  if (!Number.isFinite(n)) return padrao
  return Math.max(min, Math.min(max, n))
}

/**
 * Período a importar: padrão `[dia_trabalho_atual − dias_retroativos, dia_trabalho_atual + dias_futuros]` (reservas futuras
 * também importam). Pedido manual com `data_inicio`/`data_fim` usa as datas pedidas. Mais de 62 dias → os 62 primeiros a partir
 * do início (`truncado = true`).
 */
export function periodoTagme(entrada, config, max) {
  const limite = max ?? TAGME_MAX_DIAS
  const hoje = config && config.dia_trabalho_atual
  if (!dataValidaTagme(hoje)) throw new Error('Configuração sem dia_trabalho_atual')
  const p = (config && config.parametros) || {}
  const retro = inteiroEntre(p.dias_retroativos, 1, 0, limite - 1)
  const futuros = inteiroEntre(p.dias_futuros, 30, 0, limite - 1)
  let inicio = entrada && entrada.data_inicio ? entrada.data_inicio : null
  let fim = entrada && entrada.data_fim ? entrada.data_fim : null
  if (inicio !== null && !dataValidaTagme(inicio)) throw new Error(`Data inicial inválida: ${inicio}`)
  if (fim !== null && !dataValidaTagme(fim)) throw new Error(`Data final inválida: ${fim}`)
  if (inicio === null && fim === null) { inicio = somarDiasTagme(hoje, -retro); fim = somarDiasTagme(hoje, futuros) }
  else if (inicio === null) inicio = fim
  else if (fim === null) fim = inicio
  if (inicio > fim) throw new Error(`Período inválido: ${inicio} a ${fim}`)
  let truncado = false
  if (somarDiasTagme(inicio, limite - 1) < fim) { fim = somarDiasTagme(inicio, limite - 1); truncado = true }
  const dias = []
  for (let d = inicio; d <= fim; d = somarDiasTagme(d, 1)) dias.push(d)
  return { inicio, fim, dias, truncado }
}

/** Valor em `obj` no caminho "a.b.0.c" (ou o próprio obj para caminho vazio / "."). */
export function lerCaminho(obj, caminho) {
  if (caminho === undefined || caminho === null || caminho === '' || caminho === '.') return obj
  let atual = obj
  for (const parte of String(caminho).split('.')) {
    if (atual === null || atual === undefined) return undefined
    atual = atual[parte]
  }
  return atual
}

function preenchido(v) {
  return v !== undefined && v !== null && !(typeof v === 'string' && v.trim() === '')
}

/** 1º valor preenchido entre os caminhos (string ou lista). */
export function primeiroValor(obj, caminhos) {
  const lista = Array.isArray(caminhos) ? caminhos : [caminhos]
  for (const c of lista) {
    if (!preenchido(c)) continue
    const v = lerCaminho(obj, c)
    if (preenchido(v)) return v
  }
  return undefined
}

/** Mapeamento efetivo: o da integração por cima do padrão (campo a campo). */
export function mapeamentoTagme(parametros) {
  const m = (parametros && parametros.mapeamento) || {}
  const saida = {}
  for (const [campo, padrao] of Object.entries(MAPEAMENTO_PADRAO_TAGME)) saida[campo] = preenchido(m[campo]) && !(Array.isArray(m[campo]) && !m[campo].length) ? m[campo] : padrao
  saida.status_map = { ...STATUS_PADRAO_TAGME }
  for (const [k, v] of Object.entries(m.status_map || {})) saida.status_map[chaveStatus(k)] = v
  return saida
}

/** Lista de reservas dentro da resposta. Com `lista` explícita, ela tem de existir; no padrão, aceita também a raiz ser a lista. */
export function listaDaResposta(corpo, caminhoLista, explicito) {
  if (corpo === null || corpo === undefined || corpo === '') return []
  if (typeof corpo === 'string') throw new Error('Resposta da Tagme não é JSON (sessão expirada ou endpoint errado?)')
  const caminhos = Array.isArray(caminhoLista) ? caminhoLista : [caminhoLista]
  for (const c of caminhos) {
    const v = lerCaminho(corpo, c)
    if (Array.isArray(v)) return v
  }
  if (Array.isArray(corpo) && !explicito) return corpo
  throw new Error(`Resposta da Tagme sem a lista de reservas em "${caminhos.join('" / "')}" (ajuste parametros.mapeamento.lista)`)
}

function chaveStatus(s) {
  return String(s).normalize('NFD').replace(/\p{Diacritic}/gu, '').trim().toLowerCase().replace(/\s+/g, '_')
}

/** Status da Tagme → um de TAGME_STATUS. Desconhecido → 'pendente' (e o original fica em `status_original`). */
export function normalizarStatusTagme(valor, statusMap) {
  if (!preenchido(valor)) return 'confirmada'
  const mapa = statusMap || STATUS_PADRAO_TAGME
  const v = mapa[chaveStatus(valor)]
  return TAGME_STATUS.includes(v) ? v : 'pendente'
}

const pad2 = (n) => String(n).padStart(2, '0')

/** Data/hora local (São Paulo) de um instante em ms → { data: 'AAAA-MM-DD', hora: 'HH:MM' }. */
function localDeMs(ms) {
  const d = new Date(ms + OFFSET_SP_MIN * 60000)
  return { data: d.toISOString().slice(0, 10), hora: d.toISOString().slice(11, 16) }
}

/**
 * Interpreta data e/ou hora em formatos comuns: 'AAAA-MM-DD', 'AAAA-MM-DD HH:MM[:SS]', ISO com fuso (convertido para São Paulo),
 * 'DD/MM/AAAA [HH:MM]', epoch (s ou ms). Retorna { data|null, hora|null }.
 */
export function interpretarDataHora(v) {
  if (!preenchido(v)) return { data: null, hora: null }
  if (typeof v === 'number' || /^\d{10,13}$/.test(String(v).trim())) {
    const n = Number(v)
    return localDeMs(n < 1e12 ? n * 1000 : n)
  }
  const s = String(v).trim()
  let m = /^(\d{4}-\d{2}-\d{2})(?:[T ](\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?\s*(Z|[+-]\d{2}:?\d{2})?)?$/.exec(s)
  if (m) {
    if (m[4]) return localDeMs(Date.parse(s.replace(' ', 'T')))
    return { data: dataValidaTagme(m[1]) ? m[1] : null, hora: m[2] ? `${m[2]}:${m[3]}` : null }
  }
  m = /^(\d{2})\/(\d{2})\/(\d{4})(?:[ T](\d{2}):(\d{2}))?/.exec(s)
  if (m) {
    const iso = `${m[3]}-${m[2]}-${m[1]}`
    return { data: dataValidaTagme(iso) ? iso : null, hora: m[4] ? `${m[4]}:${m[5]}` : null }
  }
  m = /^(\d{1,2})[:h](\d{2})/.exec(s)
  if (m) return { data: null, hora: `${pad2(m[1])}:${m[2]}` }
  return { data: null, hora: null }
}

function texto(v, max) {
  if (!preenchido(v)) return null
  const t = typeof v === 'object' ? (v.name ?? v.nome ?? JSON.stringify(v)) : v
  return String(t).trim().slice(0, max || 500) || null
}

/**
 * Converte um item da Tagme no item de `ingestao_reservas`:
 * `{id_externo, data, hora, nome, telefone, email, pessoas, status, observacao, origem: 'tagme', bruto}`.
 * Sem id ou sem data → `null` (ignorado).
 */
export function normalizarReservaTagme(item, mapa) {
  if (!item || typeof item !== 'object') return null
  const m = mapa || mapeamentoTagme({})
  const id = primeiroValor(item, m.id)
  const dh = interpretarDataHora(primeiroValor(item, m.data_hora))
  const d = interpretarDataHora(primeiroValor(item, m.data))
  const h = interpretarDataHora(primeiroValor(item, m.hora))
  const data = d.data || dh.data
  if (!preenchido(id) || !data) return null
  const pessoas = Math.trunc(Number(primeiroValor(item, m.pessoas)))
  const statusOriginal = primeiroValor(item, m.status)
  const mesa = texto(primeiroValor(item, m.mesa), 60)
  const obs = texto(primeiroValor(item, m.observacao), 1000)
  return {
    id_externo: String(id),
    data,
    hora: h.hora || d.hora || dh.hora || null,
    nome: texto(primeiroValor(item, m.nome), 200),
    telefone: texto(primeiroValor(item, m.telefone), 40),
    email: texto(primeiroValor(item, m.email), 200),
    pessoas: Number.isFinite(pessoas) && pessoas > 0 ? pessoas : null,
    status: normalizarStatusTagme(statusOriginal, m.status_map),
    observacao: mesa ? (obs ? `Mesa ${mesa} — ${obs}` : `Mesa ${mesa}`).slice(0, 1000) : obs,
    origem: 'tagme',
    bruto: item,
  }
}

/** 'AAAA-MM-DD' no formato pedido pela API. `fimDoDia` = 23:59:59 nos formatos com hora. */
export function formatarDataTagme(iso, formato, fimDoDia) {
  const [a, m, d] = iso.split('-')
  switch (formato || 'AAAA-MM-DD') {
    case 'AAAA-MM-DD': return iso
    case 'DD/MM/AAAA': return `${d}/${m}/${a}`
    case 'AAAAMMDD': return `${a}${m}${d}`
    case 'iso': return `${iso}T${fimDoDia ? '23:59:59' : '00:00:00'}-03:00`
    case 'epoch': return String(Math.floor((Date.parse(`${iso}T${fimDoDia ? '23:59:59' : '00:00:00'}-03:00`)) / 1000))
    case 'epoch_ms': return String(Date.parse(`${iso}T${fimDoDia ? '23:59:59.999' : '00:00:00.000'}-03:00`))
    default: throw new Error(`Formato de data desconhecido: ${formato} (use AAAA-MM-DD, DD/MM/AAAA, AAAAMMDD, iso, epoch ou epoch_ms)`)
  }
}

/** Janelas de consulta: uma (período inteiro) ou uma por dia (`consulta.modo = 'dia'`). */
export function janelasConsulta(periodo, consulta) {
  if (consulta && consulta.modo === 'dia') return periodo.dias.map((d) => ({ inicio: d, fim: d }))
  return [{ inicio: periodo.inicio, fim: periodo.fim }]
}

/** Parâmetros (query ou corpo) de uma janela + página. */
export function parametrosConsulta(janela, consulta, paginacao, pagina) {
  const c = consulta || {}
  const fmt = c.formato_data || 'AAAA-MM-DD'
  const params = { ...(c.extras || {}) }
  if (c.modo === 'dia') params[c.param_dia || 'date'] = formatarDataTagme(janela.inicio, fmt)
  else {
    params[c.param_inicio || 'start_date'] = formatarDataTagme(janela.inicio, fmt)
    params[c.param_fim || 'end_date'] = formatarDataTagme(janela.fim, fmt, true)
  }
  if (paginacao && paginacao.param_pagina) {
    params[paginacao.param_pagina] = pagina
    if (paginacao.param_tamanho) params[paginacao.param_tamanho] = paginacao.tamanho || 100
  }
  return params
}

/** Cabeçalhos: autenticação vinda dos segredos (token com cabeçalho/prefixo configuráveis, cookie) + `segredos.cabecalhos`. */
export function cabecalhosTagme(parametros, segredos) {
  const a = (parametros && parametros.autenticacao) || {}
  const s = segredos || {}
  const h = { Accept: 'application/json' }
  if (preenchido(s.token)) {
    const prefixo = a.prefixo === undefined || a.prefixo === null ? 'Bearer' : String(a.prefixo)
    h[a.cabecalho || 'Authorization'] = prefixo ? `${prefixo} ${s.token}` : String(s.token)
  }
  if (preenchido(s.cookie)) h.Cookie = String(s.cookie)
  if (s.cabecalhos && typeof s.cabecalhos === 'object') for (const [k, v] of Object.entries(s.cabecalhos)) if (preenchido(v)) h[k] = String(v)
  return h
}

/** URL completa (base + caminho + query). */
export function urlTagme(base, caminho, params) {
  const raiz = String(base).replace(/\/+$/, '')
  const cam = String(caminho || '')
  const qs = Object.entries(params || {})
    .filter(([, v]) => v !== undefined && v !== null && v !== '')
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
    .join('&')
  const url = /^https?:\/\//.test(cam) ? cam : `${raiz}${cam.startsWith('/') ? '' : '/'}${cam}`
  return qs ? `${url}${url.includes('?') ? '&' : '?'}${qs}` : url
}

/** Requisição de uma página. GET → parâmetros na query; POST → no corpo JSON. */
export function requisicaoTagme(base, parametros, segredos, params, timeoutMs) {
  const metodo = String((parametros && parametros.metodo) || 'GET').toUpperCase()
  if (metodo !== 'GET' && metodo !== 'POST') throw new Error(`Método ${metodo} não suportado (use GET ou POST)`)
  const headers = cabecalhosTagme(parametros, segredos)
  if (metodo === 'POST') {
    headers['Content-Type'] = 'application/json'
    return { method: 'POST', url: urlTagme(base, parametros.caminho), headers, corpo: params, timeoutMs: timeoutMs || 60000 }
  }
  return { method: 'GET', url: urlTagme(base, parametros.caminho, params), headers, timeoutMs: timeoutMs || 60000 }
}

/** Confere a configuração e devolve `{ base, caminho }`. */
export function validarConfigTagme(config, baseVariavel) {
  if (!config || config.tipo !== 'tagme') throw new Error('Tipo de integração incompatível')
  const p = config.parametros || {}
  const s = config.segredos || {}
  const base = (preenchido(p.base_url) && p.base_url) || (preenchido(s.url) && s.url) || (preenchido(baseVariavel) && baseVariavel) || null
  if (!preenchido(p.caminho) && !(base && /^https?:\/\/[^/]+\/./.test(base))) {
    throw new Error('Endpoint de reservas da Tagme não configurado (Integrações → Tagme → parâmetros "caminho"). A Tagme só libera a API para parceiros — veja a documentação de implantação; enquanto isso, importe o CSV de reservas pelo sistema.')
  }
  if (!base && !/^https?:\/\//.test(String(p.caminho))) throw new Error(`URL base da Tagme não configurada (parâmetro "base_url", ex.: ${TAGME_BASE_EXEMPLO})`)
  if (!preenchido(s.token) && !preenchido(s.cookie) && !(s.cabecalhos && Object.keys(s.cabecalhos).length)) {
    throw new Error('Credencial da Tagme não configurada (Integrações → Tagme → segredos: token ou cookie)')
  }
  return { base: base || '', caminho: p.caminho || '' }
}

/**
 * Importa as reservas de uma integração 'tagme'. Não abre/fecha `sync_execucoes` (quem chama faz isso).
 * deps: { requisitar(req, opcoes) → {status, corpo, tentativas}, rpc(nome, args), baseUrl?, tentativas = 3, esperaMs = 10000,
 *         dormir?, pausaMs = 300, timeoutMs = 60000 }
 * Lê todas as janelas/páginas, normaliza, deduplica por id_externo e envia UMA chamada `ingestao_reservas` com o período inteiro
 * (a ingestão substitui o período — reimportar dá o mesmo resultado). Falha de leitura, ou nenhuma reserva reconhecível → lança (nada é gravado pela metade).
 */
export async function importarTagme(config, entrada, deps) {
  const { base } = validarConfigTagme(config, deps.baseUrl)
  const p = config.parametros || {}
  const mapa = mapeamentoTagme(p)
  const listaExplicita = !!(p.mapeamento && preenchido(p.mapeamento.lista))
  const periodo = periodoTagme(entrada, config)
  const pag = p.paginacao && p.paginacao.param_pagina ? p.paginacao : null
  const maxPaginas = pag ? inteiroEntre(pag.max_paginas, 50, 1, 500) : 1
  const tamanho = pag ? inteiroEntre(pag.tamanho, 100, 1, 10000) : null
  const opcoesHttp = { tentativas: deps.tentativas ?? 3, esperaMs: deps.esperaMs ?? 10000, dormir: deps.dormir, rotulo: 'Tagme reservas' }
  const dormir = deps.dormir || ((ms) => new Promise((ok) => setTimeout(ok, ms)))
  const pausa = deps.pausaMs ?? 300
  let tentativasMax = 1
  let chamadas = 0
  const brutos = []
  for (const janela of janelasConsulta(periodo, p.consulta)) {
    for (let n = 0; n < maxPaginas; n++) {
      const pagina = (pag ? inteiroEntre(pag.inicio, 1, 0, 1) : 1) + n
      if (chamadas > 0 && pausa > 0) await dormir(pausa)
      const req = requisicaoTagme(base, p, config.segredos, parametrosConsulta(janela, p.consulta, pag, pagina), deps.timeoutMs)
      const r = await deps.requisitar(req, opcoesHttp)
      chamadas++
      tentativasMax = Math.max(tentativasMax, r.tentativas || 1)
      const lista = listaDaResposta(r.corpo, mapa.lista, listaExplicita)
      brutos.push(...lista)
      if (!pag || !lista.length) break
      const total = Number(lerCaminho(r.corpo, pag.caminho_total_paginas || 'meta.total_pages'))
      if (Number.isFinite(total) && total > 0) { if (pagina >= total - (pag.inicio === 0 ? 1 : 0)) break }
      else if (lista.length < tamanho) break
      if (n === maxPaginas - 1) throw new Error(`Paginação da Tagme passou de ${maxPaginas} páginas`)
    }
  }
  const porId = new Map()
  let invalidos = 0
  let foraDoPeriodo = 0
  for (const b of brutos) {
    const r = normalizarReservaTagme(b, mapa)
    if (!r) { invalidos++; continue }
    if (r.data < periodo.inicio || r.data > periodo.fim) { foraDoPeriodo++; continue }
    porId.set(r.id_externo, r) // repetido (ex.: em duas páginas) → fica o último
  }
  const itens = [...porId.values()]
  if (brutos.length && invalidos === brutos.length) {
    // Mapeamento errado: NÃO chama a ingestão (que substituiria o período por uma lista vazia, apagando reservas boas).
    throw new Error(`Nenhuma das ${brutos.length} reservas recebidas tem id e data reconhecíveis — confira parametros.mapeamento (campos de um item: ${Object.keys(brutos[0] || {}).slice(0, 15).join(', ')})`)
  }
  const ret = (await deps.rpc('ingestao_reservas', { p_integracao: config.integracao_id, p_inicio: periodo.inicio, p_fim: periodo.fim, p_itens: itens })) || {}
  const ignoradosLocais = invalidos + foraDoPeriodo + (brutos.length - invalidos - foraDoPeriodo - itens.length)
  const detalhes = {
    periodo: { inicio: periodo.inicio, fim: periodo.fim, truncado: periodo.truncado },
    chamadas,
    recebidos: brutos.length,
    enviados: itens.length,
    sem_id_ou_data: invalidos,
    fora_do_periodo: foraDoPeriodo,
    repetidos: brutos.length - invalidos - foraDoPeriodo - itens.length,
    ingestao: ret,
  }
  if (!brutos.length) detalhes.aviso = 'A Tagme não devolveu reservas no período'
  return {
    status: 'sucesso',
    lidos: brutos.length,
    gravados: Number(ret.gravados) || 0,
    ignorados: ignoradosLocais + (Number(ret.ignorados) || 0),
    erro: null,
    detalhes,
    tentativas: tentativasMax,
  }
}
