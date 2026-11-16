// Mock da API do RHiD (nuvem da Control iD) — subconjunto usado por n8n/rhid/lib/rhid.mjs (docs/referencias/rhid-swagger.json).
// Montado por n8n/mocks/servidor.mjs na porta 54344 (só quando pedido: iniciarMocks({ rhid: 0 }) ou `node n8n/mocks/servidor.mjs`).
//
//   base  http://127.0.0.1:54344/v2/api.svc
//   POST /login {email, password, domain?}      e-mail/senha de RHID_MOCK → {accessToken, expiredPassword: false, isPerson: false}
//                                               senão 400 {code: 400, error: "Invalid credentials."}
//   GET  /person   (Bearer)                     → {totalRecords, records: PersonDTO[]} — funcionários demo (cpf NÚMERO, sem zeros
//                                               à esquerda) + 1 pessoa que não existe no sistema
//   GET  /device   (Bearer)                     → REP MACAW (id 55, model 1 = REP-C) e um iDFace (id 56, model 3 = Outros)
//   GET  /report/afd/download671?idEquipamento=&dataIni=&dataFinal=&nsrInicial=&limit=   (Bearer) → texto AFD 671
//        55        → registros tipo 3 (REP-C) dos funcionários de salão (marcações do mock, últimos 7 dias)
//        99000001  → REP-P (idCompany 1): cabeçalho/empresa/empregados/trailer da AMOSTRA REAL anonimizada
//                    (dados/rhid-afd-671-rep-p-amostra.txt, latin-1) + registros tipo 7 sintéticos da cozinha
//        outro     → 400 "Equipamento não encontrado"
//   GET  /report/afd_coletor_marcacao/download671?…  → 99000001: os MESMOS registros tipo 7 (o banco deduplica por CPF+instante)
//   Regras: dataIni/dataFinal obrigatórias e ≤ 90 dias (400 "Data range bigger than 90 days"), limit ≤ 50000, nsrInicial ≥.
//   O corpo do AFD vem como STRING JSON ("…\r\n…"), como a API declara (produces application/json).
//   POST /__mock/rhid/expirar → invalida os tokens (a próxima chamada recebe 401 e o cliente faz login de novo).

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const PASTA = dirname(fileURLToPath(import.meta.url))
export const RHID_MOCK = { email: 'integracao@macaw.invalid', senha: 'senha-rhid-mock', base: '/v2/api.svc', rep: 55, rep_p: 99000001 }
const AMOSTRA = readFileSync(join(PASTA, 'dados', 'rhid-afd-671-rep-p-amostra.txt'), 'latin1').split(/\r\n/).filter((l) => l !== '')

const pad = (n, t = 2) => String(n).padStart(t, '0')
const dataIso = (d) => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`
const dias = (a, b) => Math.round((Date.parse(b + 'T00:00:00Z') - Date.parse(a + 'T00:00:00Z')) / 86400000)

function crc16(texto) {
  let crc = 0xffff
  for (let i = 0; i < texto.length; i++) {
    crc ^= texto.charCodeAt(i) << 8
    for (let b = 0; b < 8; b++) crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff
  }
  return crc.toString(16).toUpperCase().padStart(4, '0')
}
function hashFalso(texto) {
  let h = ''
  let x = 2166136261
  while (h.length < 64) {
    for (let i = 0; i < texto.length; i++) { x ^= texto.charCodeAt(i); x = Math.imul(x, 16777619) >>> 0 }
    h += x.toString(16).padStart(8, '0')
  }
  return h.slice(0, 64)
}

/**
 * Cria o tratador. `marcacoes()` = marcações do mock do Control iD ([{func: {cpf, nome, jornada}, paredeMs, id}]);
 * os funcionários da cozinha vão para o REP-P (tipo 7), os demais para o REP 55 (tipo 3).
 */
export function criarTratadorRhid({ marcacoes, funcionarios }) {
  const estado = { tokens: new Set(), seq: 0, logins: 0 }
  const registro = (x) => {
    const d = new Date(x.paredeMs)
    return { dia: dataIso(d), dh: `${dataIso(d)}T${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:00-0300`, cpf: x.func.cpf.padStart(12, '0') }
  }
  function regsRep() {
    return marcacoes().filter((x) => x.func.jornada !== 'cozinha').map((x) => {
      const r = registro(x)
      const base = `${pad(x.id, 9)}3${r.dh}${r.cpf}`
      return { nsr: x.id, dia: r.dia, linha: base + crc16(base) }
    })
  }
  function regsRepP() {
    return marcacoes().filter((x) => x.func.jornada === 'cozinha').map((x, i) => {
      const r = registro(x)
      const nsr = 350 + i
      const base = `${pad(nsr, 9)}7${r.dh}${r.cpf}${r.dh}01${i % 5 === 0 ? '1' : '0'}`
      return { nsr, dia: r.dia, linha: base + hashFalso(base) }
    })
  }
  function filtrar(regs, q) {
    const ini = q.get('dataIni')
    const fim = q.get('dataFinal')
    const nsr = Number(q.get('nsrInicial') || 0)
    const limite = Number(q.get('limit') || 50000)
    return regs.filter((r) => r.dia >= ini && r.dia <= fim && r.nsr >= nsr).sort((a, b) => a.nsr - b.nsr).slice(0, limite)
  }
  function afdRep(sel) {
    const cab = `000000000112345678000190${''.padEnd(14, '0')}MACAW BEACH BAR${' '.repeat(140)}`.slice(0, 230)
    return [cab, ...sel.map((r) => r.linha), `999999999${pad(0, 9)}${pad(sel.length, 9)}${pad(0, 9)}${pad(0, 9)}${pad(0, 9)}9`].join('\r\n') + '\r\n'
  }
  function afdRepP(sel) {
    const trailer = AMOSTRA.findIndex((l) => l.startsWith('999999999'))
    const linhas = [...AMOSTRA.slice(0, trailer), ...sel.map((r) => r.linha), ...AMOSTRA.slice(trailer)]
    return linhas.join('\r\n') + '\r\n'
  }
  function pessoas() {
    const lista = funcionarios.map((f, i) => ({
      id: 1000 + i, cpf: Number(f.cpf), pis: 0, name: f.nome.toUpperCase(), registration: String(f.matricula).padStart(4, '0'),
      idDepartment: 10, idCompany: 1, status: 1, admissionDate: '2025-01-02', socialName: null, photo: null,
    }))
    lista.push({ id: 1999, cpf: 9876543210, pis: 0, name: 'PESSOA SO NO RHID', registration: '9999', idDepartment: 10, idCompany: 1, status: 1, socialName: null, photo: null })
    return lista
  }

  return function tratarRhid(req, url, corpo) {
    const b = RHID_MOCK.base
    if (url.pathname === '/__mock/rhid/expirar' && req.method === 'POST') { estado.tokens.clear(); return [200, { ok: true }] }
    if (url.pathname === '/__mock/rhid/estado') return [200, { logins: estado.logins, tokens: estado.tokens.size }]
    if (!url.pathname.startsWith(b + '/')) return [404, { code: 404, error: 'Not found' }]
    const rota = url.pathname.slice(b.length)
    if (rota === '/login') {
      if (req.method !== 'POST') return [405, { code: 405, error: 'Method not allowed' }]
      if (!corpo || typeof corpo !== 'object') return [400, { code: 400, error: 'Bad request' }]
      if (corpo.email !== RHID_MOCK.email || corpo.password !== RHID_MOCK.senha) return [400, { code: 400, error: 'Invalid credentials.' }]
      const token = `rhid-token-${++estado.seq}`
      estado.tokens.add(token)
      estado.logins++
      return [200, { accessToken: token, expiredPassword: false, revendaInadimplente: false, isPerson: false }]
    }
    const auth = String(req.headers.authorization || '')
    if (!auth.startsWith('Bearer ') || !estado.tokens.has(auth.slice(7))) return [401, 'Unauthorized']
    if (req.method !== 'GET') return [405, { code: 405, error: 'Method not allowed' }]
    if (rota === '/person') { const r = pessoas(); return [200, { totalRecords: r.length, records: r }] }
    if (rota === '/device') {
      const r = [
        { id: RHID_MOCK.rep, name: 'REP MACAW', serial: '00004004330000001', model: 1, status: 'online', numberOfPeople: 5, linkedCompanyId: 1, deviceCode: null, firstSyncPIS: null },
        { id: 56, name: 'iD Face Portaria', serial: '0M0100/000123', model: 3, status: 'online', numberOfPeople: 5, deviceCode: '01234567', statusAuth: 'A', firstSyncPIS: null },
      ]
      return [200, { totalRecords: r.length, records: r }]
    }
    const afd = rota === '/report/afd/download671'
    const coletor = rota === '/report/afd_coletor_marcacao/download671'
    if (afd || coletor) {
      const q = url.searchParams
      const ini = q.get('dataIni')
      const fim = q.get('dataFinal')
      if (!/^\d{4}-\d{2}-\d{2}$/.test(ini || '') || !/^\d{4}-\d{2}-\d{2}$/.test(fim || '') || fim < ini) return [400, 'Invalid date']
      if (dias(ini, fim) > 90) return [400, 'Data range bigger than 90 days']
      if (Number(q.get('limit') || 0) > 50000) return [400, 'Limit bigger than 50000']
      const id = Number(q.get('idEquipamento'))
      if (afd && id === RHID_MOCK.rep) return [200, JSON.stringify(afdRep(filtrar(regsRep(), q))), { 'content-type': 'application/json; charset=utf-8' }]
      if (id === RHID_MOCK.rep_p) return [200, JSON.stringify(afdRepP(filtrar(regsRepP(), q))), { 'content-type': 'application/json; charset=utf-8' }]
      return [400, 'Equipamento não encontrado']
    }
    return [404, { code: 404, error: 'Not found' }]
  }
}
