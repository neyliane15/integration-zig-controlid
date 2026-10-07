#!/usr/bin/env node
// Cenário fixo da revisão 2: equipamentos/serviços falsos com dados CONTROLADOS (calculáveis à mão), para testar ponta a ponta
// N8N (simulador) → banco → RPC/tela sem depender do gerador aleatório de `servidor.mjs`.
//
//   REP iDClass (AFD Portaria 671) com batidas que atravessam a meia-noite, uma batida faltando e uma duplicada;
//   Zig com vendas de dois garçons + balcão, linhas `Tip` (serviço) e faturamento por forma de pagamento.
//
// Datas relativas ao dia de trabalho atual D (fuso de São Paulo, virada 05:00): D-2 e D-1 (dias já encerrados).
//
// Uso: node n8n/mocks/cenario-revisao2.mjs   (REP 54351, Zig 54350; MOCK_PORTA_REP / MOCK_PORTA_ZIG mudam)
//      import { iniciarCenario, CENARIO } from './cenario-revisao2.mjs'
import { createServer } from 'node:http'

const pad = (n, t = 2) => String(n).padStart(t, '0')
const dataIso = (d) => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`
export const somarDias = (iso, n) => dataIso(new Date(Date.parse(iso + 'T00:00:00Z') + n * 86400000))
/** Dia de trabalho (SP, -03:00, virada 05:00) do instante `ms`. */
export const diaDeTrabalho = (ms = Date.now()) => dataIso(new Date(ms - 3 * 3600000 - 5 * 3600000))

export const CENARIO = {
  token: 'token-cenario-r2',
  rede: 'rede-r2',
  loja: { id: 'loja-r2', name: 'Salão Avaliação' },
  funcionarios: [
    // CPF válidos (dígitos verificadores corretos)
    { nome: 'Zeca Silva', matricula: '901', cpf: '52998224725', zig: 'ZECA SILVA ', pontos: 10 },
    { nome: 'Yara Lima', matricula: '902', cpf: '11144477735', zig: 'Yara Lima', pontos: 5 },
  ],
  // jornada "Noite teste": todos os dias 18:00 / 22:00 / 22:30 / 02:00 (previsto 450 min), tolerância diária 10, atraso 5
  jornada: ['18:00', '22:00', '22:30', '02:00'],
}

/**
 * Batidas (hora local; "+1" = dia seguinte do calendário) por dia relativo e CPF:
 *   D-2 Zeca: 18:00, 22:00, 22:31, 02:05(+1), 02:06(+1, duplicada — janela 2 min)  → 4 válidas, completo, trabalhado 240+214=454 → saldo 0 (|4| ≤ 10)
 *   D-1 Zeca: 17:58, 22:01, 02:03(+1)            → 3 válidas, incompleto, alarme "Faltou a volta do intervalo (22:30)", trabalhado 243
 *   D-1 Yara: 18:10, 22:00, 22:30, 01:55(+1)     → 4 válidas, completo, trabalhado 230+205=435 → saldo −15; atraso 10 min (> tolerância 5)
 */
export function batidas(hoje = diaDeTrabalho()) {
  const [zeca, yara] = CENARIO.funcionarios
  const d2 = somarDias(hoje, -2)
  const d1 = somarDias(hoje, -1)
  const b = (dia, hhmm, mais1, cpf) => ({ dia: mais1 ? somarDias(dia, 1) : dia, hhmm, cpf })
  return [
    b(d2, '18:00', 0, zeca.cpf), b(d2, '22:00', 0, zeca.cpf), b(d2, '22:31', 0, zeca.cpf), b(d2, '02:05', 1, zeca.cpf), b(d2, '02:06', 1, zeca.cpf),
    b(d1, '17:58', 0, zeca.cpf), b(d1, '18:10', 0, yara.cpf), b(d1, '22:00', 0, yara.cpf), b(d1, '22:01', 0, zeca.cpf),
    b(d1, '22:30', 0, yara.cpf), b(d1, '01:55', 1, yara.cpf), b(d1, '02:03', 1, zeca.cpf),
  ]
    .sort((x, y) => (x.dia + x.hhmm).localeCompare(y.dia + y.hhmm))
    .map((x, i) => ({ ...x, nsr: 101 + i }))
}

function crc16(texto) {
  let crc = 0xffff
  for (let i = 0; i < texto.length; i++) {
    crc ^= texto.charCodeAt(i) << 8
    for (let k = 0; k < 8; k++) crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff
  }
  return crc.toString(16).toUpperCase().padStart(4, '0')
}

/** AFD 671 (cabeçalho + registros tipo 3 + trailer), CRLF. Respeita `initial_nsr` / `initial_date` como o equipamento. */
export function afd(filtro, hoje = diaDeTrabalho()) {
  let regs = batidas(hoje)
  if (filtro?.initial_nsr != null) regs = regs.filter((r) => r.nsr >= Number(filtro.initial_nsr))
  else if (filtro?.initial_date) {
    const { day, month, year } = filtro.initial_date
    const ini = `${year}-${pad(month)}-${pad(day)}`
    regs = regs.filter((r) => r.dia >= ini)
  }
  const cab = `0000000001${'1'}11222333000181${''.padEnd(14, '0')}RESTAURANTE AVALIACAO${' '.repeat(136)}00004004330000001`.slice(0, 232)
  const linhas = [cab]
  for (const r of regs) {
    const base = `${pad(r.nsr, 9)}3${r.dia}T${r.hhmm}:00-0300${r.cpf.padStart(12, '0')}`
    linhas.push(base + crc16(base))
  }
  linhas.push(`999999999${pad(0, 9)}${pad(regs.length, 9)}${pad(0, 9)}${pad(0, 9)}${pad(0, 9)}9`)
  return linhas.join('\r\n') + '\r\n'
}

/**
 * Vendas da Zig (centavos). Serviço (Tip) por garçom:
 *   D-2: Zeca 1000 (venda 10000) + 333 (venda 3330); Yara 777 (venda 7770)
 *   D-1: Zeca 1234 (venda 12340); Yara 501 (venda 5010); balcão 2500 sem serviço
 * Totais: serviço 3845; vendas 40950; faturamento D-2 23210 (Crédito 15000 + PIX 8210), D-1 21585 (Crédito).
 */
export function vendas(dia, hoje = diaDeTrabalho()) {
  const d2 = somarDias(hoje, -2)
  const d1 = somarDias(hoje, -1)
  const [zeca, yara] = CENARIO.funcionarios
  const t = (n, garcom, valor, tip, hora) => ({ n, garcom, valor, tip, hora })
  const porDia = {
    [d2]: [t(1, zeca.zig, 10000, 1000, '19:10:00'), t(2, zeca.zig, 3330, 333, '23:40:00'), t(3, yara.zig, 7770, 777, '00:30:00')],
    [d1]: [t(1, zeca.zig, 12340, 1234, '20:00:00'), t(2, yara.zig, 5010, 501, '21:15:00'), t(3, '', 2500, 0, '22:45:00')],
  }
  return porDia[dia] || []
}

function saidaProdutos(dia, hoje) {
  const eventId = `evt-r2-${dia}`
  return vendas(dia, hoje).flatMap((v) => {
    // 00:xx pertence à madrugada do dia seguinte do calendário (a data de operação continua `dia`)
    const dataHora = `${v.hora < '05' ? somarDias(dia, 1) : dia}T${v.hora}`
    const comum = { transactionId: `r2-${dia}-${v.n}`, transactionDate: dataHora, eventId, eventDate: `${dia}T00:00:00`, invoiceId: null,
      fractionalAmount: null, fractionUnit: null, discountValue: null, employeeName: v.garcom, additions: null }
    const linhas = [{ ...comum, productId: 1, productSku: 'PRATO', productName: 'Prato do dia', productCategory: 'Pratos', type: 'Normal', unitValue: v.valor, count: 1 }]
    if (v.tip) linhas.push({ ...comum, productId: 900, productSku: 'SERVICO', productName: 'Serviço (10%)', productCategory: 'Serviço', type: 'Tip', unitValue: v.tip, count: 1 })
    return linhas
  })
}
function faturamento(dia, hoje) {
  const d2 = somarDias(hoje, -2)
  const d1 = somarDias(hoje, -1)
  const ev = { eventId: `evt-r2-${dia}`, eventDate: `${dia}T00:00:00`, eventName: `Operação ${dia}` }
  if (dia === d2) return [{ ...ev, paymentId: 1, paymentName: 'Crédito', value: 15000 }, { ...ev, paymentId: 3, paymentName: 'PIX', value: 8210 }]
  if (dia === d1) return [{ ...ev, paymentId: 1, paymentName: 'Crédito', value: 21585 }]
  return []
}

function ler(req) {
  return new Promise((ok) => {
    const partes = []
    req.on('data', (c) => partes.push(c))
    req.on('end', () => {
      const t = Buffer.concat(partes).toString('utf8')
      try { ok(t ? JSON.parse(t) : null) } catch { ok(null) }
    })
  })
}

/** Sobe REP + Zig do cenário. `portas` 0 = porta livre. Devolve { portas, chamadas, fechar() }. */
export async function iniciarCenario({ rep = 54351, zig = 54350, host = '127.0.0.1' } = {}) {
  const chamadas = []
  const responder = (res, status, corpo, tipo = 'application/json') => {
    res.writeHead(status, { 'content-type': tipo })
    res.end(typeof corpo === 'string' ? corpo : JSON.stringify(corpo))
  }
  const sRep = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x')
    const corpo = await ler(req)
    chamadas.push({ servidor: 'rep', caminho: url.pathname, corpo })
    if (url.pathname === '/login.fcgi') return corpo?.login === 'admin' && corpo?.password === 'admin' ? responder(res, 200, { session: 's-r2' }) : responder(res, 401, { error: 'Invalid login or password' })
    if (url.searchParams.get('session') !== 's-r2') return responder(res, 401, { error: 'Invalid session' })
    if (url.pathname === '/logout.fcgi') return responder(res, 200, {})
    if (url.pathname === '/load_users.fcgi') {
      const users = CENARIO.funcionarios.map((f, i) => ({ id: i + 1, name: f.nome.toUpperCase(), cpf: Number(f.cpf), pis: 0, registration: Number(f.matricula), code: 0, templates_count: 1, bars: '', rfid: 0, admin: false, password: '' }))
      const off = Number(corpo?.offset || 0)
      return responder(res, 200, { users: corpo?.limit != null ? users.slice(off, off + Number(corpo.limit)) : users })
    }
    if (url.pathname === '/get_afd.fcgi') return responder(res, 200, afd(corpo), 'application/octet-stream')
    if (url.pathname === '/system_information.fcgi') return responder(res, 200, { time: Math.floor(Date.now() / 1000) })
    return responder(res, 404, { error: 'Not found' })
  })
  const sZig = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x')
    chamadas.push({ servidor: 'zig', caminho: url.pathname + url.search })
    if (req.headers.authorization !== CENARIO.token) return responder(res, 401, { message: 'Unauthorized' })
    const rota = url.pathname.replace(/^\/integration/, '')
    const q = url.searchParams
    if (rota === '/erp/lojas') return responder(res, 200, q.get('rede') === CENARIO.rede ? [CENARIO.loja] : [])
    const dia = q.get('dtinicio')
    if (q.get('loja') !== CENARIO.loja.id) return responder(res, 404, { message: 'Loja não encontrada' })
    if (dia !== q.get('dtfim')) return responder(res, 400, { message: 'um dia por vez' })
    const hoje = diaDeTrabalho()
    if (rota === '/erp/saida-produtos') return responder(res, 200, saidaProdutos(dia, hoje))
    if (rota === '/erp/faturamento') return responder(res, 200, faturamento(dia, hoje))
    if (rota === '/erp/compradores' || rota === '/erp/faturamento/detalhesMaquinaIntegrada') return responder(res, 200, [])
    return responder(res, 404, { message: 'Rota não encontrada' })
  })
  const ouvir = (s, p) => new Promise((ok) => s.listen(p, host, () => ok(s.address().port)))
  const portas = { rep: await ouvir(sRep, rep), zig: await ouvir(sZig, zig) }
  return {
    portas,
    chamadas,
    fechar: () => Promise.all([sRep, sZig].map((s) => new Promise((ok) => s.close(ok)))),
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const c = await iniciarCenario({ rep: Number(process.env.MOCK_PORTA_REP || 54351), zig: Number(process.env.MOCK_PORTA_ZIG || 54350) })
  console.log(`cenário revisão 2: REP http://127.0.0.1:${c.portas.rep} (admin/admin) · Zig http://127.0.0.1:${c.portas.zig}/integration (token ${CENARIO.token}, rede ${CENARIO.rede})`)
  console.log(`dia de trabalho atual ${diaDeTrabalho()}`)
}
