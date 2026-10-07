#!/usr/bin/env node
// Servidores HTTP falsos da Zig e do Control iD para testar os workflows do N8N sem equipamento nem conta real.
// Node puro, sem dependências. Uso: `node n8n/mocks/servidor.mjs` (ou `npm run n8n:mocks`).
//
//   54340  Zig            base http://127.0.0.1:54340/integration   header Authorization: token-mock
//   54341  Control iD acesso (iDFace/iDAccess/iDFlex)   login admin/admin → sessão "sessao-mock"
//   54342  Control iD REP (iDClass, AFD Portaria 671)  login admin/admin → sessão "sessao-rep-mock"
//
// Variáveis opcionais:
//   MOCK_AGORA=2026-10-06T12:00:00-03:00   fixa o relógio (padrão: hora real). Os dados são relativos a ele.
//   MOCK_PORTA_ZIG / MOCK_PORTA_ACESSO / MOCK_PORTA_REP   (padrões 54340 / 54341 / 54342)
//   MOCK_HOST (padrão 127.0.0.1)   MOCK_LOG=1 (registra cada chamada no console)
//
// Rotas de controle (em qualquer porta):
//   GET  /__mock/estado      → { agora, dia_trabalho, chamadas: n }
//   GET  /__mock/chamadas    → últimas 500 chamadas [{porta, metodo, caminho, status}]
//   POST /__mock/falhas      {"caminho": "/integration/erp/faturamento", "status": 429, "vezes": 2}
//                            → as próximas N chamadas cujo caminho começa com `caminho` respondem `status`
//   POST /__mock/reset       → volta ao estado inicial (falhas, chamadas, sessões, objetos gravados)
//   GET  /__estado           → o que foi gravado: { objetos (acesso), imagens (fotos por user_id), rep_usuarios, historico }
//
// Control iD acesso aceita: login, logout, session_is_valid, load_objects, count_objects, create_objects, modify_objects,
//   destroy_objects (users, cards, qrcodes, groups, user_groups, time_zones, time_spans, access_rules, user_access_rules,
//   group_access_rules, portal_access_rules, access_rule_time_zones; access_logs só leitura), user_set_image (corpo
//   application/octet-stream, JPEG/PNG), user_set_image_list (base64), user_destroy_image, user_hash_password
//   ({password} → {password: sha256(salt+senha) hex, salt} determinístico). Cascata ao apagar usuário.
// Control iD REP aceita: login, logout, load_users, add_users, update_users, remove_users (por CPF/PIS), get_afd.
// Erro simulável: qualquer texto contendo "#ERRO" em create/modify (acesso) ou add/update_users (REP) → 400 do equipamento;
//   chaves duplicadas (cards.value, user_access_rules…) e FKs inexistentes também → 400, como no equipamento real.
//
// Casos fixos de erro da Zig: rede "rede-erro" lista "loja-500" (sempre 500) e "loja-429" (sempre 429, Retry-After: 1).

import { createServer } from 'node:http'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const PASTA = dirname(fileURLToPath(import.meta.url))
const lerJson = (nome) => JSON.parse(readFileSync(join(PASTA, 'dados', nome), 'utf8'))

const DEMO = lerJson('funcionarios.json')
const ZIG = lerJson('zig.json')
const OFFSET_MIN = -180 // America/Sao_Paulo (sem horário de verão desde 2019)
const VIRADA_MIN = 5 * 60
const SESSAO_ACESSO = 'sessao-mock'
const SESSAO_REP = 'sessao-rep-mock'

// ----------------------------------------------------------------------------- tempo
const pad = (n, t = 2) => String(n).padStart(t, '0')
const dataIso = (d) => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`
const somarDias = (iso, n) => dataIso(new Date(Date.parse(iso + 'T00:00:00Z') + n * 86400000))
const dow = (iso) => new Date(iso + 'T00:00:00Z').getUTCDay()
const serialDia = (iso) => Math.round((Date.parse(iso + 'T00:00:00Z') - Date.parse('2026-01-01T00:00:00Z')) / 86400000)
const minutos = (hhmm) => Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3, 5))

function agoraMs() {
  return process.env.MOCK_AGORA ? Date.parse(process.env.MOCK_AGORA) : Date.now()
}
/** "Parede" local (ms como se fosse UTC) de um instante real. */
const paredeLocal = (ms) => ms + OFFSET_MIN * 60000
/** Dia de trabalho (contrato §2.4) de um instante real. */
const diaDeTrabalho = (ms) => dataIso(new Date(paredeLocal(ms) - VIRADA_MIN * 60000))

// ----------------------------------------------------------------------------- aleatório determinístico
function hash(texto) {
  let h = 2166136261
  for (let i = 0; i < texto.length; i++) {
    h ^= texto.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}
function gerador(semente) {
  let a = hash(semente)
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
const inteiro = (rnd, min, max) => min + Math.floor(rnd() * (max - min + 1))
const escolher = (rnd, lista) => lista[Math.floor(rnd() * lista.length)]

// ----------------------------------------------------------------------------- estado
const estado = { falhas: [], chamadas: [], sessoes: new Set(), objetos: {}, imagens: {}, repUsuarios: [], historico: [] }
function reset() {
  estado.falhas = []
  estado.chamadas = []
  estado.sessoes = new Set()
  estado.objetos = objetosIniciais()
  estado.imagens = {}
  estado.repUsuarios = repUsuariosIniciais()
  estado.historico = []
}

// ============================================================================= ZIG
/** Vendas determinísticas de uma loja num dia de operação. */
function vendasDoDia(loja, dia) {
  const rnd = gerador(`zig|${loja}|${dia}`)
  const fimDeSemana = [0, 5, 6].includes(dow(dia))
  const nTransacoes = fimDeSemana ? inteiro(rnd, 24, 32) : inteiro(rnd, 12, 20)
  const produtos = ZIG.produtos.filter((p) => p.tipo === 'Normal')
  const couvert = ZIG.produtos.find((p) => p.tipo === 'Couvert')
  const eventId = `evt-${loja}-${dia}`
  const transacoes = []
  for (let t = 0; t < nTransacoes; t++) {
    const transactionId = `${loja}-${dia.replaceAll('-', '')}-${pad(t + 1, 4)}`
    const minutoDoDia = 18 * 60 + inteiro(rnd, 0, 7 * 60 + 30) // 18:00 → 01:30
    const diaHora = minutoDoDia >= 1440 ? somarDias(dia, 1) : dia
    const m = minutoDoDia % 1440
    const transactionDate = `${diaHora}T${pad(Math.floor(m / 60))}:${pad(m % 60)}:${pad(inteiro(rnd, 0, 59))}`
    const balcao = rnd() < 0.12
    const garcom = balcao ? '' : escolher(rnd, ZIG.garcons)
    const invoiceId = `nf-${transactionId}`
    const linhas = []
    const nLinhas = inteiro(rnd, 1, 4)
    for (let l = 0; l < nLinhas; l++) {
      const p = escolher(rnd, produtos)
      const count = inteiro(rnd, 1, 3)
      const desconto = rnd() < 0.08 ? Math.round(p.preco * count * 0.1) : 0
      linhas.push({
        transactionId, transactionDate, eventId, eventDate: `${dia}T00:00:00`, invoiceId,
        productId: p.id, productSku: p.sku, productName: p.nome, productCategory: p.categoria,
        type: p.tipo, unitValue: p.preco, count, fractionalAmount: null, fractionUnit: null,
        discountValue: desconto || null, employeeName: garcom,
        additions: p.categoria === 'Drinks' && rnd() < 0.3 ? [{ productId: 301, productName: 'Dose extra', count: 1, value: 800 }] : null,
      })
    }
    if (fimDeSemana && rnd() < 0.5) {
      linhas.push({
        transactionId, transactionDate, eventId, eventDate: `${dia}T00:00:00`, invoiceId,
        productId: couvert.id, productSku: couvert.sku, productName: couvert.nome, productCategory: couvert.categoria,
        type: 'Couvert', unitValue: couvert.preco, count: inteiro(rnd, 1, 4), fractionalAmount: null, fractionUnit: null,
        discountValue: null, employeeName: garcom, additions: null,
      })
    }
    const subtotal = linhas.reduce((s, x) => s + x.unitValue * x.count - (x.discountValue || 0), 0)
    let tip = 0
    if (!balcao && rnd() < 0.9) {
      tip = Math.round((subtotal * ZIG.percentual_servico) / 100)
      linhas.push({
        transactionId, transactionDate, eventId, eventDate: `${dia}T00:00:00`, invoiceId,
        productId: 900, productSku: 'SERVICO', productName: 'Serviço (10%)', productCategory: 'Serviço',
        type: 'Tip', unitValue: tip, count: 1, fractionalAmount: null, fractionUnit: null,
        discountValue: null, employeeName: garcom, additions: null,
      })
    }
    // forma de pagamento ponderada
    const totalPeso = ZIG.formas_pagamento.reduce((s, f) => s + f.peso, 0)
    let sorteio = rnd() * totalPeso
    let forma = ZIG.formas_pagamento[0]
    for (const f of ZIG.formas_pagamento) {
      if ((sorteio -= f.peso) < 0) { forma = f; break }
    }
    const bandeira = forma.bandeiras.length ? escolher(rnd, forma.bandeiras) : null
    transacoes.push({ transactionId, transactionDate, invoiceId, eventId, garcom, linhas, subtotal, tip, forma, bandeira })
  }
  return { eventId, transacoes }
}

function zigSaidaProdutos(loja, dia) {
  return vendasDoDia(loja, dia).transacoes.flatMap((t) => t.linhas)
}
function zigFaturamento(loja, dia) {
  const { eventId, transacoes } = vendasDoDia(loja, dia)
  const porForma = new Map()
  for (const t of transacoes) porForma.set(t.forma.id, (porForma.get(t.forma.id) || 0) + t.subtotal + t.tip)
  return ZIG.formas_pagamento.filter((f) => porForma.has(f.id)).map((f) => ({
    eventId, eventDate: `${dia}T00:00:00`, eventName: `Operação ${dia}`, paymentId: f.id, paymentName: f.nome, value: porForma.get(f.id),
  }))
}
function zigBandeiras(loja, dia) {
  const { eventId, transacoes } = vendasDoDia(loja, dia)
  const out = []
  for (const f of ZIG.formas_pagamento.filter((x) => x.bandeiras.length)) {
    const valores = new Map()
    for (const t of transacoes.filter((x) => x.forma.id === f.id)) valores.set(t.bandeira, (valores.get(t.bandeira) || 0) + t.subtotal + t.tip)
    if (valores.size) out.push({ eventId, paymentId: f.id, paymentName: f.nome, values: [...valores].map(([cardBrand, totalValue]) => ({ cardBrand, totalValue })) })
  }
  return out
}
function zigCompradores(loja, dia) {
  return vendasDoDia(loja, dia).transacoes.map((t, i) => ({
    transactionId: t.transactionId,
    // dados pessoais FALSOS — a ingestão DEVE descartá-los (LGPD)
    userDocument: `000000000${pad(i, 2)}`, userDocumentType: 'CPF', userName: `Cliente ${i + 1}`,
    userPhone: '+5511900000000', userEmail: `cliente${i + 1}@exemplo.invalid`,
    productsValue: t.subtotal, tipValue: t.tip,
  }))
}
function zigInvoices(loja, dia) {
  return vendasDoDia(loja, dia).transacoes.map((t) => ({ invoiceId: t.invoiceId, transactionId: t.transactionId, value: t.subtotal + t.tip, issuedAt: t.transactionDate, status: 'Issued' }))
}
function zigCheckins(loja, dia) {
  return vendasDoDia(loja, dia).transacoes.filter((_, i) => i % 2 === 0).map((t, i) => ({ checkinId: `ck-${t.transactionId}`, eventId: t.eventId, date: t.transactionDate, guests: 1 + (i % 4) }))
}

const ROTAS_ZIG = {
  '/erp/saida-produtos': zigSaidaProdutos,
  '/erp/faturamento': zigFaturamento,
  '/erp/faturamento/detalhesMaquinaIntegrada': zigBandeiras,
  '/erp/compradores': zigCompradores,
  '/erp/invoice': zigInvoices,
  '/erp/checkins': zigCheckins,
}
const PAGINADAS = new Set(['/erp/invoice', '/erp/checkins'])
const lojasConhecidas = () => new Set(Object.values(ZIG.redes).flat().map((l) => l.id))

function tratarZig(req, url) {
  if (!url.pathname.startsWith('/integration/')) return [404, { message: 'Rota não encontrada' }]
  if (req.headers.authorization !== ZIG.token) return [401, { message: 'Unauthorized' }]
  const rota = url.pathname.slice('/integration'.length)
  const q = url.searchParams
  if (req.method !== 'GET') return [405, { message: 'Method not allowed' }]
  if (rota === '/erp/lojas') {
    const rede = q.get('rede')
    if (!rede) return [400, { message: 'Parâmetro rede obrigatório' }]
    return [200, ZIG.redes[rede] || []]
  }
  const gerar = ROTAS_ZIG[rota]
  if (!gerar) return [404, { message: 'Rota não encontrada' }]
  const ini = q.get('dtinicio')
  const fim = q.get('dtfim')
  const loja = q.get('loja')
  const re = /^\d{4}-\d{2}-\d{2}$/
  if (!re.test(ini || '') || !re.test(fim || '') || fim < ini) return [400, { message: 'dtinicio/dtfim inválidos (AAAA-MM-DD)' }]
  if (!loja) return [400, { message: 'Parâmetro loja obrigatório' }]
  if (!lojasConhecidas().has(loja)) return [404, { message: 'Loja não encontrada' }]
  if (loja === 'loja-500') return [500, { message: 'Erro interno simulado' }]
  if (loja === 'loja-429') return [429, { message: 'Too Many Requests' }, { 'retry-after': '1' }]
  const hoje = diaDeTrabalho(agoraMs())
  const dados = []
  for (let d = ini; d <= fim && d <= hoje; d = somarDias(d, 1)) dados.push(...gerar(loja, d))
  if (!PAGINADAS.has(rota)) return [200, dados]
  const tamanho = Number(q.get('pageSize') || q.get('limit') || ZIG.paginacao.tamanho_pagina)
  const pagina = Math.max(1, Number(q.get('page') || 1))
  const totalPaginas = Math.max(1, Math.ceil(dados.length / tamanho))
  return [200, { data: dados.slice((pagina - 1) * tamanho, pagina * tamanho), page: pagina, pageSize: tamanho, total: dados.length, totalPages: totalPaginas, hasNextPage: pagina < totalPaginas }]
}

// ============================================================================= CONTROL iD (batidas comuns)
/**
 * Marcações "reais" de todos os funcionários demo nos últimos 7 dias de trabalho + hoje (até agora).
 * Cada uma: { func, dia, indice, paredeMs (hora local como se fosse UTC), id }.
 */
function marcacoes() {
  const agora = agoraMs()
  const hoje = diaDeTrabalho(agora)
  const falha = DEMO.falha_programada
  const diaFalha = somarDias(hoje, -falha.dias_atras)
  const lista = []
  for (let k = 7; k >= 0; k--) {
    const dia = somarDias(hoje, -k)
    const doDia = []
    for (const f of DEMO.funcionarios) {
      const j = DEMO.jornadas[f.jornada]
      if (!j.dias_semana.includes(dow(dia))) continue
      j.horarios.forEach((hhmm, indice) => {
        if (f.matricula === falha.matricula && dia === diaFalha && indice === falha.indice_horario) return
        const rnd = gerador(`ponto|${f.matricula}|${dia}|${indice}`)
        let m = minutos(hhmm)
        if (m < VIRADA_MIN) m += 1440
        const paredeMs = Date.parse(dia + 'T00:00:00Z') + (m + inteiro(rnd, -4, 4)) * 60000 + inteiro(rnd, 0, 59) * 1000
        if (paredeMs - OFFSET_MIN * 60000 > agora) return // ainda não aconteceu
        doDia.push({ func: f, dia, indice, paredeMs })
      })
    }
    doDia.sort((a, b) => a.paredeMs - b.paredeMs || a.func.id_controlid - b.func.id_controlid)
    doDia.forEach((x, i) => { x.id = serialDia(dia) * 100 + i + 1 })
    lista.push(...doDia)
  }
  return lista
}

// ----------------------------------------------------------------------------- acesso (54341)
// Objetos guardados em memória (resetados por POST /__mock/reset). `access_logs` é gerado (somente leitura).
const OBJETOS_GRAVAVEIS = ['users', 'cards', 'qrcodes', 'groups', 'user_groups', 'time_zones', 'time_spans', 'access_rules',
  'user_access_rules', 'group_access_rules', 'portal_access_rules', 'access_rule_time_zones']
const CHAVES_UNICAS = { cards: ['value'], qrcodes: ['value'], user_access_rules: ['user_id', 'access_rule_id'],
  user_groups: ['user_id', 'group_id'], group_access_rules: ['group_id', 'access_rule_id'],
  portal_access_rules: ['portal_id', 'access_rule_id'], access_rule_time_zones: ['access_rule_id', 'time_zone_id'] }
const SEM_ID = new Set(['user_access_rules', 'user_groups', 'group_access_rules', 'portal_access_rules', 'access_rule_time_zones'])
function objetosIniciais() {
  return {
    users: DEMO.funcionarios.map((f) => ({ id: f.id_controlid, registration: f.matricula, name: f.nome, password: '', salt: '', begin_time: 0, end_time: 0, image_timestamp: 0 })),
    cards: [], qrcodes: [], groups: [{ id: 1, name: 'Padrão' }], user_groups: [],
    time_zones: [{ id: 1, name: 'Sempre liberado' }],
    time_spans: [{ id: 1, time_zone_id: 1, start: 0, end: 86399, sun: 1, mon: 1, tue: 1, wed: 1, thu: 1, fri: 1, sat: 1, hol1: 1, hol2: 1, hol3: 1 }],
    access_rules: [{ id: 1, name: 'Liberado sempre', type: 1, priority: 0 }],
    user_access_rules: [], group_access_rules: [{ group_id: 1, access_rule_id: 1 }], portal_access_rules: [{ portal_id: 1, access_rule_id: 1 }],
    access_rule_time_zones: [{ access_rule_id: 1, time_zone_id: 1 }],
  }
}
function usuariosAcesso() {
  return estado.objetos.users
}
function logsAcesso() {
  return marcacoes().map((x) => ({
    id: x.id, time: Math.floor(x.paredeMs / 1000), event: 7, device_id: 478435, identifier_id: 0,
    user_id: x.func.id_controlid, portal_id: 1, identification_rule_id: 0, card_value: 0, qrcode_value: '', pin_value: '',
    confidence: 1500 + (x.id % 300), mask: 0,
  }))
}
const OPERADORES = {
  '>=': (a, b) => a >= b, '>': (a, b) => a > b, '<=': (a, b) => a <= b, '<': (a, b) => a < b, '=': (a, b) => a == b, '==': (a, b) => a == b, '!=': (a, b) => a != b,
  'IN': (a, b) => Array.isArray(b) && b.some((v) => v == a), 'in': (a, b) => Array.isArray(b) && b.some((v) => v == a),
}
function filtrar(lista, where) {
  if (!where || typeof where !== 'object') return lista
  const conds = []
  for (const campos of Object.values(where)) {
    for (const [campo, regra] of Object.entries(campos || {})) {
      if (regra !== null && typeof regra === 'object' && !Array.isArray(regra)) {
        for (const [op, valor] of Object.entries(regra)) {
          if (!OPERADORES[op]) throw new ErroEquip(`Unknown operator: ${op}`)
          conds.push((x) => OPERADORES[op](x[campo], valor))
        }
      } else if (Array.isArray(regra)) conds.push((x) => regra.some((v) => v == x[campo]))
      else conds.push((x) => x[campo] == regra)
    }
  }
  return lista.filter((x) => conds.every((c) => c(x)))
}
class ErroEquip extends Error {
  constructor(msg, status = 400) { super(msg); this.status = status }
}
/** Caso de erro simulável: qualquer valor de texto contendo "#ERRO" é recusado como o equipamento recusaria. */
function conferirErroSimulado(valores) {
  for (const v of valores) for (const x of Object.values(v || {})) if (typeof x === 'string' && x.includes('#ERRO')) throw new ErroEquip('Simulated device error (#ERRO)')
}
function conferirUnicidade(objeto, lista, novo, ignorar) {
  const chaves = CHAVES_UNICAS[objeto]
  if (!chaves) return
  if (lista.some((x) => x !== ignorar && chaves.every((k) => x[k] == novo[k]))) throw new ErroEquip(`UNIQUE constraint failed: ${objeto}.${chaves.join(', ')}`)
}
function conferirReferencias(objeto, v) {
  const o = estado.objetos
  const existe = (tab, id) => o[tab].some((x) => x.id == id)
  if ('user_id' in v && ['cards', 'qrcodes', 'user_access_rules', 'user_groups'].includes(objeto) && !existe('users', v.user_id)) throw new ErroEquip('FOREIGN KEY constraint failed: user_id')
  if ('access_rule_id' in v && !existe('access_rules', v.access_rule_id)) throw new ErroEquip('FOREIGN KEY constraint failed: access_rule_id')
  if ('time_zone_id' in v && !existe('time_zones', v.time_zone_id)) throw new ErroEquip('FOREIGN KEY constraint failed: time_zone_id')
  if ('group_id' in v && !existe('groups', v.group_id)) throw new ErroEquip('FOREIGN KEY constraint failed: group_id')
}
function apagarDependentes(objeto, removidos) {
  const o = estado.objetos
  const ids = new Set(removidos.map((x) => x.id))
  const tirar = (tab, campo) => { o[tab] = o[tab].filter((x) => !ids.has(x[campo])) }
  if (objeto === 'users') {
    tirar('cards', 'user_id'); tirar('qrcodes', 'user_id'); tirar('user_access_rules', 'user_id'); tirar('user_groups', 'user_id')
    for (const id of ids) delete estado.imagens[id]
  }
  if (objeto === 'time_zones') { tirar('time_spans', 'time_zone_id'); tirar('access_rule_time_zones', 'time_zone_id') }
  if (objeto === 'access_rules') { tirar('user_access_rules', 'access_rule_id'); tirar('group_access_rules', 'access_rule_id'); tirar('portal_access_rules', 'access_rule_id'); tirar('access_rule_time_zones', 'access_rule_id') }
  if (objeto === 'groups') { tirar('user_groups', 'group_id'); tirar('group_access_rules', 'group_id') }
}
function listaDoObjeto(objeto) {
  if (objeto === 'access_logs') return logsAcesso()
  if (OBJETOS_GRAVAVEIS.includes(objeto)) return estado.objetos[objeto]
  throw new ErroEquip(`Unknown object: ${objeto}`)
}
function gravavel(objeto) {
  if (!OBJETOS_GRAVAVEIS.includes(objeto)) throw new ErroEquip(objeto === 'access_logs' ? 'Object access_logs is read-only in the mock' : `Unknown object: ${objeto}`)
  return estado.objetos[objeto]
}

async function tratarAcesso(req, url, corpo) {
  const rota = url.pathname
  if (req.method !== 'POST') return [405, { error: 'Method not allowed' }]
  if (rota === '/login.fcgi') {
    if (corpo?.login === 'admin' && corpo?.password === 'admin') {
      estado.sessoes.add(SESSAO_ACESSO)
      return [200, { session: SESSAO_ACESSO }]
    }
    return [401, { error: 'Invalid login or password', code: 1 }]
  }
  const sessao = url.searchParams.get('session')
  if (!sessao || !estado.sessoes.has(sessao) || sessao !== SESSAO_ACESSO) return [401, { error: 'Invalid session', code: 1 }]
  try {
    if (rota === '/session_is_valid.fcgi') return [200, { session_is_valid: true }]
    if (rota === '/logout.fcgi') {
      estado.sessoes.delete(sessao)
      return [200, {}]
    }
    if (rota === '/load_objects.fcgi') {
      const objeto = corpo?.object
      let lista = filtrar(listaDoObjeto(objeto), corpo.where)
      if (!SEM_ID.has(objeto)) lista = [...lista].sort((a, b) => a.id - b.id)
      const offset = Number(corpo.offset || 0)
      if (corpo.limit != null) lista = lista.slice(offset, offset + Number(corpo.limit))
      else if (offset) lista = lista.slice(offset)
      return [200, { [objeto]: lista }]
    }
    if (rota === '/count_objects.fcgi') return [200, { count: filtrar(listaDoObjeto(corpo?.object), corpo?.where).length }]
    if (rota === '/create_objects.fcgi') {
      const objeto = corpo?.object
      const lista = gravavel(objeto)
      if (!Array.isArray(corpo.values) || !corpo.values.length) throw new ErroEquip('Field values must be a non-empty array')
      conferirErroSimulado(corpo.values)
      const novos = []
      let proximo = Math.max(0, ...lista.map((x) => Number(x.id) || 0)) + 1
      for (const v of corpo.values) {
        if (objeto === 'users' && (typeof v?.name !== 'string' || !v.name.trim())) throw new ErroEquip('Field name is required')
        if (objeto === 'cards' && v?.value == null) throw new ErroEquip('Field value is required')
        const novo = SEM_ID.has(objeto) ? { ...v } : { ...v, id: v.id ?? proximo++ }
        if (objeto === 'users') Object.assign(novo, { registration: v.registration != null ? String(v.registration) : '', password: v.password ?? '', salt: v.salt ?? '', begin_time: v.begin_time ?? 0, end_time: v.end_time ?? 0, image_timestamp: 0 })
        if (!SEM_ID.has(objeto) && [...lista, ...novos].some((x) => x.id == novo.id)) throw new ErroEquip(`UNIQUE constraint failed: ${objeto}.id`)
        conferirReferencias(objeto, novo)
        conferirUnicidade(objeto, [...lista, ...novos], novo)
        novos.push(novo)
      }
      lista.push(...novos) // tudo ou nada, como uma transação
      estado.historico.push({ servidor: 'acesso', acao: 'create_objects', objeto, quantidade: novos.length })
      return [200, SEM_ID.has(objeto) ? {} : { ids: novos.map((x) => x.id) }]
    }
    if (rota === '/modify_objects.fcgi') {
      const objeto = corpo?.object
      const lista = gravavel(objeto)
      if (!corpo.values || typeof corpo.values !== 'object' || Array.isArray(corpo.values)) throw new ErroEquip('Field values must be an object')
      if (!corpo.where) throw new ErroEquip('Field where is required')
      conferirErroSimulado([corpo.values])
      const alvos = filtrar(lista, corpo.where)
      for (const alvo of alvos) {
        const novo = { ...alvo, ...corpo.values }
        if (objeto === 'users' && 'registration' in corpo.values) novo.registration = String(corpo.values.registration ?? '')
        conferirReferencias(objeto, novo)
        conferirUnicidade(objeto, lista, novo, alvo)
      }
      for (const alvo of alvos) Object.assign(alvo, corpo.values, objeto === 'users' && 'registration' in corpo.values ? { registration: String(corpo.values.registration ?? '') } : {})
      estado.historico.push({ servidor: 'acesso', acao: 'modify_objects', objeto, quantidade: alvos.length })
      return [200, { changes: alvos.length }]
    }
    if (rota === '/destroy_objects.fcgi') {
      const objeto = corpo?.object
      const lista = gravavel(objeto)
      if (!corpo.where) throw new ErroEquip('Field where is required')
      const alvos = filtrar(lista, corpo.where)
      estado.objetos[objeto] = lista.filter((x) => !alvos.includes(x))
      apagarDependentes(objeto, alvos)
      estado.historico.push({ servidor: 'acesso', acao: 'destroy_objects', objeto, quantidade: alvos.length })
      return [200, { changes: alvos.length }]
    }
    if (rota === '/user_hash_password.fcgi') {
      const senha = corpo?.password
      if (senha === undefined || senha === null || String(senha) === '') throw new ErroEquip('Field password is required')
      const salt = createHash('sha256').update(`salt|${senha}`).digest('hex').slice(0, 32)
      const hashHex = createHash('sha256').update(salt + String(senha)).digest('hex')
      return [200, { password: hashHex, salt }]
    }
    if (rota === '/user_set_image.fcgi') {
      const id = Number(url.searchParams.get('user_id'))
      const u = estado.objetos.users.find((x) => x.id === id)
      if (!u) throw new ErroEquip('User not found')
      const bytes = corpo?.__bytes ?? 0
      if (!bytes) throw new ErroEquip('Empty image')
      if (corpo?.__inicio && !corpo.__inicio.startsWith('ffd8') && !corpo.__inicio.startsWith('89504e47')) throw new ErroEquip('Invalid image format (expected JPEG or PNG)')
      const ts = Number(url.searchParams.get('timestamp') || Math.floor(agoraMs() / 1000))
      estado.imagens[id] = { bytes, timestamp: ts, match: url.searchParams.get('match') }
      u.image_timestamp = ts
      estado.historico.push({ servidor: 'acesso', acao: 'user_set_image', user_id: id, bytes })
      return [200, { success: true, scores: { bounds_width: 300, horizontal_center_offset: 0, vertical_center_offset: 0, center_pose_quality: 900, sharpness_quality: 900 } }]
    }
    if (rota === '/user_set_image_list.fcgi') {
      const lista = corpo?.user_images
      if (!Array.isArray(lista)) throw new ErroEquip('Field user_images must be an array')
      const resultados = lista.map((it) => {
        const u = estado.objetos.users.find((x) => x.id === Number(it.user_id))
        if (!u) return { user_id: it.user_id, success: false, errors: [{ code: 1, message: 'User not found' }] }
        const bytes = Buffer.from(String(it.image || ''), 'base64').length
        if (!bytes) return { user_id: it.user_id, success: false, errors: [{ code: 2, message: 'Empty image' }] }
        estado.imagens[u.id] = { bytes, timestamp: Number(it.timestamp || 0) }
        u.image_timestamp = Number(it.timestamp || 0)
        return { user_id: u.id, success: true }
      })
      estado.historico.push({ servidor: 'acesso', acao: 'user_set_image_list', quantidade: lista.length })
      return [200, { results: resultados }]
    }
    if (rota === '/user_destroy_image.fcgi') {
      const ids = corpo?.user_ids ?? (corpo?.user_id != null ? [corpo.user_id] : [])
      for (const id of ids) { delete estado.imagens[id]; const u = estado.objetos.users.find((x) => x.id == id); if (u) u.image_timestamp = 0 }
      return [200, {}]
    }
  } catch (e) {
    if (e instanceof ErroEquip) return [e.status, { error: e.message, code: 1 }]
    throw e
  }
  return [404, { error: 'Not found', code: 1 }]
}

// ----------------------------------------------------------------------------- REP (54342)
function repUsuariosIniciais() {
  return DEMO.funcionarios.map((f) => ({ id: f.id_controlid, name: f.nome.toUpperCase(), cpf: Number(f.cpf), pis: 0, registration: Number(f.matricula), code: 0, templates_count: 1, bars: '', rfid: 0, admin: false, password: '' }))
}
function usuariosRep() {
  return estado.repUsuarios
}
/** Identificador do usuário no REP: CPF (Portaria 671) ou, sem CPF, PIS. */
const idRep = (u) => Number(u?.cpf || 0) || Number(u?.pis || 0)
function crc16(texto) {
  let crc = 0xffff
  for (let i = 0; i < texto.length; i++) {
    crc ^= texto.charCodeAt(i) << 8
    for (let b = 0; b < 8; b++) crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff
  }
  return crc.toString(16).toUpperCase().padStart(4, '0')
}
/** AFD Portaria 671 (registros 3 com 50 colunas) — veja contrato §12.4. */
function afd(filtro) {
  const regs = marcacoes().map((x) => {
    const d = new Date(x.paredeMs)
    const dh = `${dataIso(d)}T${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:00-0300`
    const base = `${pad(x.id, 9)}3${dh}${x.func.cpf.padStart(12, '0')}`
    return { nsr: x.id, dia: dataIso(d), linha: base + crc16(base) }
  })
  let sel = regs
  if (filtro?.initial_nsr != null) sel = regs.filter((r) => r.nsr >= Number(filtro.initial_nsr))
  else if (filtro?.initial_date) {
    const { day, month, year } = filtro.initial_date
    const ini = `${year}-${pad(month)}-${pad(day)}`
    sel = regs.filter((r) => r.dia >= ini)
  }
  const cab = `0000000001${'1'.padEnd(1)}12345678000190${''.padEnd(14, '0')}BAR BOSSA NOVA${' '.repeat(136)}00004004330000001`.slice(0, 232)
  const linhas = [cab]
  // um registro tipo 4 (ajuste de relógio) para exercitar o parser — deve ser ignorado
  if (sel.length) {
    const p = sel[0]
    const dh = p.linha.slice(10, 34)
    const r4 = `${pad(Math.max(0, p.nsr - 1), 9)}4${dh}${dh}${'0'.padStart(11, '0')}`
    linhas.push(r4 + crc16(r4))
  }
  linhas.push(...sel.map((r) => r.linha))
  linhas.push(`999999999${pad(0, 9)}${pad(sel.length, 9)}${pad(0, 9)}${pad(0, 9)}${pad(0, 9)}9`)
  return linhas.join('\r\n') + '\r\n'
}

async function tratarRep(req, url, corpo) {
  const rota = url.pathname
  if (req.method !== 'POST') return [405, { error: 'Method not allowed' }]
  if (rota === '/login.fcgi') {
    if (corpo?.login === 'admin' && corpo?.password === 'admin') {
      estado.sessoes.add(SESSAO_REP)
      return [200, { session: SESSAO_REP }]
    }
    return [401, { error: 'Invalid login or password', code: 1 }]
  }
  const sessao = url.searchParams.get('session')
  if (!sessao || !estado.sessoes.has(sessao) || sessao !== SESSAO_REP) return [401, { error: 'Invalid session', code: 1 }]
  if (rota === '/logout.fcgi') {
    estado.sessoes.delete(sessao)
    return [200, {}]
  }
  if (rota === '/load_users.fcgi') {
    let lista = usuariosRep()
    if (corpo?.limit != null) lista = lista.slice(Number(corpo.offset || 0), Number(corpo.offset || 0) + Number(corpo.limit))
    return [200, { users: lista }]
  }
  if (rota === '/add_users.fcgi' || rota === '/update_users.fcgi') {
    const lista = corpo?.users
    if (!Array.isArray(lista) || !lista.length) return [400, { error: 'Field users must be a non-empty array', code: 1 }]
    const adicionar = rota === '/add_users.fcgi'
    const pendentes = []
    for (const u of lista) {
      if (Object.values(u || {}).some((x) => typeof x === 'string' && x.includes('#ERRO'))) return [400, { error: 'Simulated device error (#ERRO)', code: 1 }]
      const id = idRep(u)
      if (!id) return [400, { error: 'User must have cpf or pis', code: 1 }]
      if (adicionar && (typeof u.name !== 'string' || !u.name.trim())) return [400, { error: 'Field name is required', code: 1 }]
      const existente = estado.repUsuarios.find((x) => idRep(x) === id)
      if (adicionar && (existente || pendentes.some((p) => idRep(p.u) === id))) return [400, { error: `User already exists: ${id}`, code: 1 }]
      if (!adicionar && !existente) return [400, { error: `User not found: ${id}`, code: 1 }]
      pendentes.push({ u, existente })
    }
    let proximo = Math.max(0, ...estado.repUsuarios.map((x) => x.id)) + 1
    for (const { u, existente } of pendentes) {
      const normal = { ...u }
      if ('cpf' in normal) normal.cpf = Number(normal.cpf || 0)
      if ('pis' in normal) normal.pis = Number(normal.pis || 0)
      if ('registration' in normal) normal.registration = Number(normal.registration || 0)
      if (existente) Object.assign(existente, normal)
      else estado.repUsuarios.push({ id: proximo++, cpf: 0, pis: 0, registration: 0, code: 0, templates_count: 0, bars: '', rfid: 0, admin: false, password: '', ...normal })
    }
    estado.historico.push({ servidor: 'rep', acao: rota.slice(1, -5), quantidade: pendentes.length })
    return [200, {}]
  }
  if (rota === '/remove_users.fcgi') {
    const lista = corpo?.users
    if (!Array.isArray(lista) || !lista.length) return [400, { error: 'Field users must be a non-empty array', code: 1 }]
    const ids = new Set(lista.map((x) => (typeof x === 'object' ? idRep(x) : Number(x))))
    for (const id of ids) if (!estado.repUsuarios.some((x) => idRep(x) === id)) return [400, { error: `User not found: ${id}`, code: 1 }]
    const antes = estado.repUsuarios.length
    estado.repUsuarios = estado.repUsuarios.filter((x) => !ids.has(idRep(x)))
    estado.historico.push({ servidor: 'rep', acao: 'remove_users', quantidade: antes - estado.repUsuarios.length })
    return [200, {}]
  }
  if (rota === '/get_afd.fcgi') return [200, afd(corpo), { 'content-type': 'application/octet-stream' }]
  return [404, { error: 'Not found', code: 1 }]
}

// ============================================================================= HTTP
function lerCorpo(req) {
  return new Promise((resolve) => {
    const partes = []
    req.on('data', (c) => partes.push(c))
    req.on('end', () => {
      const bruto = Buffer.concat(partes)
      const tipo = String(req.headers['content-type'] || '')
      if (tipo.startsWith('application/octet-stream') || tipo.startsWith('image/')) return resolve({ __binario: true, __bytes: bruto.length, __inicio: bruto.subarray(0, 4).toString('hex') })
      const texto = bruto.toString('utf8')
      if (!texto) return resolve(undefined)
      try { resolve(JSON.parse(texto)) } catch { resolve({ __invalido: texto }) }
    })
  })
}

function controle(req, url, corpo) {
  const p = url.pathname
  if (p === '/__mock/estado') return [200, { agora: new Date(agoraMs()).toISOString(), dia_trabalho: diaDeTrabalho(agoraMs()), chamadas: estado.chamadas.length, falhas: estado.falhas }]
  if (p === '/__mock/chamadas') return [200, estado.chamadas]
  if (p === '/__estado' || p === '/__mock/gravado') return [200, { objetos: estado.objetos, imagens: estado.imagens, rep_usuarios: estado.repUsuarios, historico: estado.historico }]
  if (p === '/__mock/reset' && req.method === 'POST') { reset(); return [200, { ok: true }] }
  if (p === '/__mock/falhas' && req.method === 'POST') {
    if (!corpo?.caminho || !corpo?.status) return [400, { erro: 'informe caminho e status' }]
    estado.falhas.push({ porta: corpo.porta ?? null, caminho: corpo.caminho, status: Number(corpo.status), vezes: Number(corpo.vezes ?? 1) })
    return [200, { ok: true, falhas: estado.falhas }]
  }
  return null
}

function criarServidor(nome, porta, tratar) {
  return createServer(async (req, res) => {
    const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`)
    const corpo = await lerCorpo(req)
    let resposta
    try {
      const ehControle = url.pathname.startsWith('/__mock/') || url.pathname === '/__estado'
      resposta = ehControle ? controle(req, url, corpo) : null
      if (!resposta) {
        const falha = estado.falhas.find((f) => f.vezes > 0 && url.pathname.startsWith(f.caminho) && (f.porta == null || f.porta === porta))
        if (falha) {
          falha.vezes--
          resposta = [falha.status, { message: `Falha simulada ${falha.status}` }, falha.status === 429 ? { 'retry-after': '1' } : {}]
        } else if (corpo && corpo.__invalido) resposta = [400, { error: 'Invalid JSON' }]
        else resposta = await tratar(req, url, corpo)
      }
    } catch (e) {
      resposta = [500, { message: String(e?.message || e) }]
    }
    const [status, dados, cabecalhos = {}] = resposta
    if (!url.pathname.startsWith('/__mock/') && url.pathname !== '/__estado') {
      estado.chamadas.push({ porta, servidor: nome, metodo: req.method, caminho: url.pathname + url.search, status })
      if (estado.chamadas.length > 500) estado.chamadas.shift()
    }
    if (process.env.MOCK_LOG === '1') console.log(`[${nome}] ${req.method} ${url.pathname}${url.search} → ${status}`)
    const texto = typeof dados === 'string'
    res.writeHead(status, { 'content-type': texto ? 'text/plain; charset=utf-8' : 'application/json; charset=utf-8', ...cabecalhos })
    res.end(texto ? dados : JSON.stringify(dados))
  })
}

/** Sobe os três mocks. Retorna `{ fechar(), portas }`. Portas 0 = aleatórias (útil em testes). */
export async function iniciarMocks({ host = process.env.MOCK_HOST || '127.0.0.1', zig = Number(process.env.MOCK_PORTA_ZIG || 54340), acesso = Number(process.env.MOCK_PORTA_ACESSO || 54341), rep = Number(process.env.MOCK_PORTA_REP || 54342) } = {}) {
  reset()
  const defs = [['zig', zig, tratarZig], ['acesso', acesso, tratarAcesso], ['rep', rep, tratarRep]]
  const servidores = {}
  const portas = {}
  for (const [nome, porta, tratar] of defs) {
    const s = criarServidor(nome, porta, tratar)
    await new Promise((ok, falhou) => { s.once('error', falhou); s.listen(porta, host, ok) })
    servidores[nome] = s
    portas[nome] = s.address().port
  }
  return {
    portas,
    host,
    fechar: () => Promise.all(Object.values(servidores).map((s) => new Promise((ok) => s.close(ok)))),
  }
}

// exportados para testes
export const _interno = { estado, vendasDoDia, zigFaturamento, zigSaidaProdutos, marcacoes, afd, diaDeTrabalho, agoraMs }

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const m = await iniciarMocks()
  const h = m.host
  console.log('Mocks do Meu Dia de Gerente no ar:')
  console.log(`  Zig ............ http://${h}:${m.portas.zig}/integration   (Authorization: ${ZIG.token}, rede=rede-mock)`)
  console.log(`  Control iD acesso http://${h}:${m.portas.acesso}           (admin/admin)`)
  console.log(`  Control iD REP .. http://${h}:${m.portas.rep}           (admin/admin)`)
  console.log(`  Dia de trabalho do mock: ${diaDeTrabalho(agoraMs())}  (MOCK_AGORA=${process.env.MOCK_AGORA || 'relógio real'})`)
  const parar = () => m.fechar().then(() => process.exit(0))
  process.on('SIGINT', parar)
  process.on('SIGTERM', parar)
}
