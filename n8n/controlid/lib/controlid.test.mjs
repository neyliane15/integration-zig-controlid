// Testes unitários de lib/controlid.mjs (sem rede: o equipamento é simulado por uma função http falsa).
// Rodam com `node --test n8n/controlid/lib/` e com `npm test` (vitest).
import assert from 'node:assert/strict'
import * as L from './controlid.mjs'

const { describe, it } = process.env.VITEST ? await import('vitest') : await import('node:test')
const semEspera = async () => {}
const ISO = (y, m, d, h = 0, mi = 0, s = 0) => Date.UTC(y, m - 1, d, h, mi, s) / 1000

function configAcesso(extra = {}) {
  return {
    integracao_id: 'a0000000-0000-4000-8000-000000000102', empresa_id: 'a0000000-0000-4000-8000-00000000000a',
    tipo: 'controlid_acesso', nome: 'iDFace', ativa: true,
    parametros: { modelo: 'iDFace', dias_retroativos: 2, eventos_validos: [7], relogio_em_hora_local: true },
    segredos: { url: '192.168.0.50/', login: 'admin', senha: 'admin' },
    cursor: {}, fuso: 'America/Sao_Paulo', virada_dia: '05:00:00', dia_trabalho_atual: '2026-10-06',
    ...extra,
  }
}

/** Equipamento falso: `rotas[endpoint](corpo, url)` → [status, corpo]; registra chamadas. */
function equipamento(rotas, { sessao = 'S1' } = {}) {
  const chamadas = []
  const estado = { sessaoValida: sessao }
  const http = async (req) => {
    const u = new URL(req.url)
    const ep = u.pathname.slice(1)
    chamadas.push({ ep, corpo: req.corpo, sessao: u.searchParams.get('session'), req })
    if (ep === 'login.fcgi') {
      if (rotas['login.fcgi']) return wrap(await rotas['login.fcgi'](req.corpo, u, estado))
      return req.corpo.login === 'admin' && req.corpo.password === 'admin'
        ? wrap([200, { session: estado.sessaoValida }]) : wrap([401, { error: 'Invalid login' }])
    }
    if (ep === 'logout.fcgi') return wrap([200, {}])
    if (u.searchParams.get('session') !== estado.sessaoValida) return wrap([401, { error: 'Invalid session' }])
    const r = rotas[ep]
    if (!r) return wrap([404, { error: 'Not found' }])
    return wrap(await r(req.corpo, u, estado))
  }
  const wrap = ([status, corpo]) => ({ status, corpo: typeof corpo === 'string' ? corpo : JSON.stringify(corpo) })
  return { http, chamadas, estado }
}

describe('utilitários', () => {
  it('documentos, url, uuid, texto', () => {
    assert.equal(L.normalizarDocumento(52998224725), '52998224725')
    assert.equal(L.normalizarDocumento('529.982.247-25'), '52998224725')
    assert.equal(L.normalizarDocumento(1234567890), '01234567890')
    assert.equal(L.normalizarDocumento('052998224725'), '52998224725')
    assert.equal(L.normalizarDocumento('152998224725'), null)
    assert.equal(L.normalizarDocumento(0), null)
    assert.equal(L.normalizarDocumento(null), null)
    assert.equal(L.normalizarUrl(' 192.168.0.50/ '), 'http://192.168.0.50')
    assert.equal(L.normalizarUrl('https://rep.local:443//'), 'https://rep.local:443')
    const u = 'a0000000-0000-4000-8000-000000000102'
    assert.equal(L.extrairUuid(u), u)
    assert.equal(L.extrairUuid({ data: u }), u)
    assert.equal(L.extrairUuid({ ingestao_sync_iniciar: u }), u)
    assert.equal(L.extrairUuid({ error: 'x' }), null)
    assert.equal(L.lerJson('{"a":1}').a, 1)
    assert.equal(L.lerJson(''), null)
    assert.equal(L.lerJson('000000001'), undefined)
    assert.equal(L.comoTexto(new TextEncoder().encode('AFD')), 'AFD')
    assert.equal(L.mensagemDeErro({ message: 'x', description: 'y' }), 'x — y')
    assert.equal(L.mensagemDeErro({ error: { message: 'z' } }), 'z')
  })
})

describe('tempo e fuso', () => {
  it('relógio em hora local: time = parede gravada como UTC → instante_local', () => {
    assert.deepEqual(L.unixParaInstante(ISO(2026, 10, 5, 17, 2, 11), true), { instante_local: '2026-10-05T17:02:11' })
    assert.deepEqual(L.unixParaInstante(ISO(2026, 10, 5, 20, 2, 11), false), { instante: '2026-10-05T20:02:11Z' })
    assert.equal(L.unixParaInstante(0, true), null)
    assert.equal(L.unixParaInstante('x', true), null)
  })

  it('T sem cursor = (dia atual − dias_retroativos) 00:00 no referencial do equipamento', () => {
    const base = { cursor: {}, diaTrabalhoAtual: '2026-10-06', diasRetroativos: 2, fuso: 'America/Sao_Paulo' }
    assert.equal(L.calcularInicioAcesso({ ...base, horaLocal: true }), ISO(2026, 10, 4))
    assert.equal(L.calcularInicioAcesso({ ...base, horaLocal: false }), ISO(2026, 10, 4, 3)) // 00:00 −03 = 03:00Z
  })

  it('T com cursor = max(cursor − 1 dia, piso); data_inicio ignora cursor e piso', () => {
    const base = { diaTrabalhoAtual: '2026-10-06', diasRetroativos: 2, fuso: 'America/Sao_Paulo' }
    const cursor = { ultimo_instante: '2026-10-05T20:02:11+00:00' } // 17:02:11 em SP
    assert.equal(L.calcularInicioAcesso({ ...base, cursor, horaLocal: true }), ISO(2026, 10, 4, 17, 2, 11))
    assert.equal(L.calcularInicioAcesso({ ...base, cursor, horaLocal: false }), ISO(2026, 10, 4, 20, 2, 11))
    const velho = { ultimo_instante: '2026-09-01T12:00:00Z' }
    assert.equal(L.calcularInicioAcesso({ ...base, cursor: velho, horaLocal: true }), ISO(2026, 10, 4))
    assert.equal(L.calcularInicioAcesso({ ...base, cursor: velho, dataInicio: '2026-08-20', horaLocal: true }), ISO(2026, 8, 20))
    assert.equal(L.calcularFimAcesso({ dataFim: '2026-08-25', viradaDia: '05:00:00', fuso: 'America/Sao_Paulo', horaLocal: true }), ISO(2026, 8, 26, 5))
    assert.equal(L.calcularFimAcesso({ dataFim: null }), null)
  })

  it('fuso com horário de verão (America/New_York) e virada de ano', () => {
    assert.equal(L.localParaUtcMs(2026, 3, 8, 12, 0, 0, 'America/New_York'), Date.UTC(2026, 2, 8, 16)) // EDT
    assert.equal(L.localParaUtcMs(2026, 1, 8, 12, 0, 0, 'America/New_York'), Date.UTC(2026, 0, 8, 17)) // EST
    assert.equal(L.dataMaisDias('2026-01-01', -2), '2025-12-30')
    assert.equal(L.instanteParaUnix('2026-10-05T20:00:00Z', 'America/Sao_Paulo', true), ISO(2026, 10, 5, 17))
    assert.equal(L.hojeNoFuso('America/Sao_Paulo', Date.UTC(2026, 9, 6, 2)), '2026-10-05')
  })
})

describe('corpos e mapeamentos', () => {
  it('corpos', () => {
    assert.deepEqual(L.corpoAccessLogs(100, null, 1000, 2000),
      { object: 'access_logs', where: { access_logs: { time: { '>=': 100 } } }, limit: 1000, offset: 2000 })
    assert.deepEqual(L.corpoAccessLogs(100, 200).where.access_logs.time, { '>=': 100, '<': 200 })
    assert.deepEqual(L.corpoUsuariosAcesso(null), { object: 'users' })
    assert.deepEqual(L.corpoAfd({ cursor: { ultimo_nsr: 456 }, diaTrabalhoAtual: '2026-10-06', diasRetroativos: 2 }), { initial_nsr: 457 })
    assert.deepEqual(L.corpoAfd({ cursor: { ultimo_nsr: '456' }, diaTrabalhoAtual: '2026-10-06', diasRetroativos: 2 }), { initial_nsr: 457 })
    assert.deepEqual(L.corpoAfd({ cursor: {}, diaTrabalhoAtual: '2026-10-06', diasRetroativos: 2 }), { initial_date: { day: 4, month: 10, year: 2026 } })
    assert.deepEqual(L.corpoAfd({ cursor: { ultimo_nsr: 9 }, diaTrabalhoAtual: '2026-10-06', dataInicio: '2026-09-01' }), { initial_date: { day: 1, month: 9, year: 2026 } })
  })

  it('access_logs → batidas', () => {
    assert.deepEqual(L.mapearAccessLog({ id: 98123, time: ISO(2026, 10, 5, 17, 2, 11), event: 7, user_id: 12 }, true),
      { id_externo: '98123', user_id: '12', evento: 7, instante_local: '2026-10-05T17:02:11' })
    assert.deepEqual(L.mapearAccessLog({ id: 1, time: ISO(2026, 10, 5, 20), user_id: 0 }, false),
      { id_externo: '1', user_id: '0', instante: '2026-10-05T20:00:00Z' })
    assert.equal(L.mapearAccessLog({ time: 1 }, true), null)
  })

  it('usuários de acesso e REP', () => {
    assert.deepEqual(L.mapearUsuarioAcesso({ id: 12, registration: '3', name: 'CARLA DIAS' }),
      { id: '12', registration: '3', name: 'CARLA DIAS', cpf: null, pis: null })
    assert.deepEqual(L.mapearUsuarioAcesso({ id: 5, registration: '', name: 'X' }).registration, null)
    assert.deepEqual(L.mapearUsuarioRep({ name: 'ANA', cpf: 52998224725, pis: 0, registration: 1 }, 'cpf'),
      { id: '52998224725', registration: '1', name: 'ANA', cpf: '52998224725', pis: null })
    assert.equal(L.mapearUsuarioRep({ name: 'ANA', cpf: 52998224725, pis: 0 }, 'pis'), null)
    assert.equal(L.mapearUsuarioRep({ name: 'B', pis: 12345678901 }, 'pis').id, '12345678901')
  })

  it('lerConfig valida e aplica padrões', () => {
    const c = L.lerConfig(configAcesso())
    assert.equal(c.url, 'http://192.168.0.50')
    assert.equal(c.horaLocal, true)
    assert.equal(c.diasRetroativos, 2)
    assert.equal(c.tentativas, 3)
    assert.equal(c.esperaMs, 10000)
    assert.equal(L.lerConfig(configAcesso({ parametros: { relogio_em_hora_local: false } })).horaLocal, false)
    assert.throws(() => L.lerConfig(configAcesso({ tipo: 'zig' })), /Tipo de integração incompatível/)
    assert.throws(() => L.lerConfig(configAcesso({ ativa: false })), /Integração inativa/)
    assert.throws(() => L.lerConfig(configAcesso({ segredos: {} })), /URL do equipamento/)
    assert.throws(() => L.lerConfig(configAcesso({ segredos: { url: 'x' } })), /login e a senha/)
    assert.throws(() => L.lerConfig({ error: { message: 'Integração não encontrada' } }), /Integração não encontrada/)
    assert.throws(() => L.lerConfig(null), /não recebida/)
  })
})

describe('cliente com sessão', () => {
  it('retenta timeout e 5xx, depois responde', async () => {
    let n = 0
    const eq = equipamento({ 'load_objects.fcgi': () => [200, { users: [] }] })
    const http = async (req) => {
      if (req.url.includes('load_objects') && n++ < 2) {
        if (n === 1) throw Object.assign(new Error('timeout of 30000ms exceeded'), { code: 'ECONNABORTED' })
        return { status: 503, corpo: 'ocupado' }
      }
      return eq.http(req)
    }
    const esperas = []
    const c = L.criarCliente({ http, url: 'http://x', login: 'admin', senha: 'admin', esperar: async (ms) => esperas.push(ms) })
    assert.deepEqual(await c.chamar('load_objects.fcgi', { object: 'users' }), { users: [] })
    assert.equal(c.tentativas, 3)
    assert.deepEqual(esperas, [10000, 10000])
  })

  it('desiste após 3 tentativas com mensagem clara', async () => {
    const http = async () => { throw Object.assign(new Error('connect ECONNREFUSED'), { code: 'ECONNREFUSED' }) }
    const c = L.criarCliente({ http, url: 'http://x', login: 'a', senha: 'b', esperar: semEspera })
    await assert.rejects(c.entrar(), /login\.fcgi após 3 tentativa\(s\): conexão recusada/)
  })

  it('sessão expirada → novo login e repete a chamada', async () => {
    let logins = 0
    const eq = equipamento({
      'login.fcgi': (corpo, u, estado) => [200, { session: (estado.sessaoValida = 'S' + ++logins) }],
      'load_objects.fcgi': () => [200, { users: [{ id: 1 }] }],
    })
    const c = L.criarCliente({ http: eq.http, url: 'http://x', login: 'admin', senha: 'admin', esperar: semEspera })
    await c.entrar()
    eq.estado.sessaoValida = 'outra' // o equipamento reiniciou
    const r = await c.chamar('load_objects.fcgi', { object: 'users' })
    assert.equal(r.users.length, 1)
    assert.equal(c.logins, 2)
  })

  it('login recusado não retenta; erro do equipamento vira exceção', async () => {
    const eq = equipamento({ 'load_objects.fcgi': () => [400, { error: 'Unknown object: x' }] })
    const ruim = L.criarCliente({ http: eq.http, url: 'http://x', login: 'admin', senha: 'errada', esperar: semEspera })
    await assert.rejects(ruim.entrar(), /Login recusado/)
    assert.equal(eq.chamadas.filter((c) => c.ep === 'login.fcgi').length, 1)
    const bom = L.criarCliente({ http: eq.http, url: 'http://x', login: 'admin', senha: 'admin', esperar: semEspera })
    await assert.rejects(bom.chamar('load_objects.fcgi', { object: 'x' }), (e) => e.status === 400 && /Unknown object/.test(e.message))
    assert.equal(await bom.sair(), true)
    assert.equal(await bom.sair(), false) // sem sessão, não chama de novo
  })

  it('paginação para em página curta e em equipamento que ignora offset', async () => {
    const todos = Array.from({ length: 25 }, (_, i) => ({ id: i + 1 }))
    const paginado = await L.carregarPaginado(async (c) => ({ users: todos.slice(c.offset, c.offset + c.limit) }), L.corpoUsuariosAcesso, 'users', { tamanhoPagina: 10 })
    assert.equal(paginado.itens.length, 25)
    assert.equal(paginado.paginas, 3)
    const ignora = await L.carregarPaginado(async () => ({ users: todos }), L.corpoUsuariosAcesso, 'users', { tamanhoPagina: 10 })
    assert.equal(ignora.itens.length, 25)
    assert.equal(ignora.paginas, 2)
  })
})

describe('orquestradores (importação)', () => {
  it('buscarUsuarios no acesso: mapeia e sempre faz logout', async () => {
    const eq = equipamento({ 'load_objects.fcgi': (c) => [200, { users: c.offset ? [] : [{ id: 1, registration: '1', name: 'ANA' }, { id: 2, name: 'BRUNO' }] }] })
    const r = await L.buscarUsuarios({ http: eq.http, config: configAcesso(), esperar: semEspera })
    assert.equal(r.ok, true)
    assert.deepEqual(r.usuarios.map((u) => u.id), ['1', '2'])
    assert.equal(r.detalhes.logout, true)
    assert.equal(eq.chamadas.at(-1).ep, 'logout.fcgi')
  })

  it('buscarUsuarios: lista vazia é erro (não apaga ninguém) e faz logout', async () => {
    const eq = equipamento({ 'load_objects.fcgi': () => [200, { users: [] }] })
    const r = await L.buscarUsuarios({ http: eq.http, config: configAcesso(), esperar: semEspera })
    assert.equal(r.ok, false)
    assert.match(r.erro, /nenhum usuário/)
    assert.equal(eq.chamadas.at(-1).ep, 'logout.fcgi')
  })

  it('buscarUsuarios no REP: cai para chamada sem paginação se o modelo recusar limit', async () => {
    const eq = equipamento({ 'load_users.fcgi': (c) => (c.limit ? [400, { error: 'Invalid parameter' }] : [200, { users: [{ name: 'ANA', cpf: 52998224725 }, { name: 'SEM CPF' }] }]) })
    const r = await L.buscarUsuarios({ http: eq.http, config: configAcesso({ tipo: 'controlid_rep', parametros: { identificador: 'cpf' } }), esperar: semEspera })
    assert.equal(r.ok, true)
    assert.equal(r.usuarios[0].id, '52998224725')
    assert.equal(r.ignorados, 1)
  })

  it('buscarBatidas no acesso: janela, filtro fora da janela, desvio de relógio', async () => {
    const agora = Date.UTC(2026, 9, 6, 15) // 12:00 em SP
    let pedido
    const eq = equipamento({
      'system_information.fcgi': () => [200, { time: ISO(2026, 10, 6, 12, 10) }],
      'load_objects.fcgi': (c) => {
        pedido = c
        return [200, { access_logs: c.offset ? [] : [
          { id: 1, time: ISO(2026, 10, 5, 17), event: 7, user_id: 1 },
          { id: 2, time: ISO(2026, 9, 1, 17), event: 7, user_id: 1 }, // fora da janela (equipamento ignorou o where)
          { id: 1, time: ISO(2026, 10, 5, 17), event: 7, user_id: 1 },
        ] }]
      },
    })
    const r = await L.buscarBatidas({ http: eq.http, config: configAcesso(), entrada: {}, esperar: semEspera, agoraMs: agora })
    assert.equal(r.ok, true)
    assert.equal(pedido.where.access_logs.time['>='], ISO(2026, 10, 4))
    assert.deepEqual(r.batidas, [{ id_externo: '1', user_id: '1', evento: 7, instante_local: '2026-10-05T17:00:00' }])
    assert.equal(r.detalhes.fora_da_janela, 1)
    assert.equal(r.detalhes.relogio_desvio_segundos, 600)
    assert.match(r.detalhes.aviso_relogio, /10 min/)
  })

  it('buscarBatidas no REP: pede AFD pelo NSR e devolve o texto', async () => {
    let pedido
    const eq = equipamento({ 'get_afd.fcgi': (c) => { pedido = c; return [200, '0000000023051020261702012345678901\r\n'] } })
    const r = await L.buscarBatidas({ http: eq.http, config: configAcesso({ tipo: 'controlid_rep', cursor: { ultimo_nsr: 1 } }), entrada: {}, esperar: semEspera })
    assert.deepEqual(pedido, { initial_nsr: 2 })
    assert.match(r.afd, /^000000002/)
    assert.equal(eq.chamadas.at(-1).ep, 'logout.fcgi')
  })

  it('erro no meio: ok=false, mensagem e logout mesmo assim', async () => {
    const eq = equipamento({ 'get_afd.fcgi': () => [500, 'falhou'] })
    const r = await L.buscarBatidas({ http: eq.http, config: configAcesso({ tipo: 'controlid_rep' }), entrada: {}, esperar: semEspera })
    assert.equal(r.ok, false)
    assert.match(r.erro, /get_afd\.fcgi após 3/)
    assert.equal(r.tentativas, 3)
    assert.equal(eq.chamadas.at(-1).ep, 'logout.fcgi')
  })
})

describe('resumos', () => {
  const exec = 'e0000000-0000-4000-8000-000000000001'
  it('batidas: sucesso, parcial e erro', () => {
    const busca = { ok: true, lidos: 3, ignorados: 0, detalhes: {}, tentativas: 1, execucao_id: exec }
    const lotes = [{ lote: [1, 2] }, { lote: [3] }]
    const ok = L.resumirBatidas({ busca, lotes, respostas: [{ lidos: 2, gravados: 1, ignorados: 0, duplicados: 1, cursor: { ultimo_id: '2' } }, { lidos: 1, gravados: 1, ignorados: 0 }] })
    assert.equal(ok[0].finalizacao.p_status, 'sucesso')
    assert.equal(ok[0].finalizacao.p_gravados, 2)
    assert.equal(ok[0].finalizacao.p_ignorados, 1)
    assert.deepEqual(ok[0].finalizacao.p_detalhes.cursor, { ultimo_id: '2' })
    assert.deepEqual(ok[0].saida.execucao_ids, [exec])
    const parcial = L.resumirBatidas({ busca, lotes, respostas: [{ error: { message: 'timeout' } }, { lidos: 1, gravados: 1 }] })
    assert.equal(parcial[0].finalizacao.p_status, 'parcial')
    assert.equal(parcial[0].finalizacao.p_ignorados, 2)
    assert.match(parcial[0].finalizacao.p_erro, /1 de 2 lote/)
    const erro = L.resumirBatidas({ busca: { ok: false, erro: 'Login recusado', lidos: 0, execucao_id: exec } })
    assert.equal(erro[0].finalizacao.p_status, 'erro')
    assert.equal(erro[0].saida.erro, 'Login recusado')
    const vazio = L.resumirBatidas({ busca, lotes: [{ sem_lote: true, afd_resumo: null }], respostas: [] })
    assert.equal(vazio[0].finalizacao.p_status, 'sucesso')
  })

  it('usuários: grava detalhes da ingestão; falha do Supabase vira erro', () => {
    const busca = { ok: true, lidos: 2, ignorados: 0, detalhes: {}, execucao_id: 'x' }
    const ok = L.resumirUsuarios({ busca, resposta: { lidos: 2, gravados: 2, ignorados: 0, inseridos: 1, vinculados_automaticamente: 1 } })
    assert.equal(ok[0].finalizacao.p_status, 'sucesso')
    assert.equal(ok[0].finalizacao.p_detalhes.vinculados_automaticamente, 1)
    const ruim = L.resumirUsuarios({ busca, resposta: { error: { message: 'Integração inativa' } } })
    assert.equal(ruim[0].finalizacao.p_status, 'erro')
    assert.match(ruim[0].finalizacao.p_erro, /Integração inativa/)
  })

  it('montarSaida combina várias execuções', () => {
    const s = L.montarSaida([
      { p_execucao: 'a', p_status: 'sucesso', p_lidos: 1, p_gravados: 1, p_ignorados: 0 },
      { p_execucao: 'b', p_status: 'erro', p_lidos: 2, p_gravados: 0, p_ignorados: 0, p_erro: 'x' },
    ])
    assert.deepEqual(s, { execucao_ids: ['a', 'b'], status: 'parcial', lidos: 3, gravados: 1, ignorados: 0, erro: 'x' })
  })
})

describe('adaptador N8N', () => {
  it('monta o pedido do this.helpers.httpRequest', async () => {
    let pedido
    const helpers = { httpRequest: async (p) => { pedido = p; return { statusCode: 200, body: '{"session":"s"}' } } }
    const http = L.adaptadorHttpN8n(helpers)
    const r = await http({ metodo: 'POST', url: 'https://rep/login.fcgi', corpo: { login: 'a' }, timeoutMs: 5000, texto: true })
    assert.deepEqual(r, { status: 200, corpo: '{"session":"s"}' })
    assert.equal(pedido.body, '{"login":"a"}')
    assert.equal(pedido.skipSslCertificateValidation, true)
    assert.equal(pedido.ignoreHttpStatusErrors, true)
    assert.equal(pedido.encoding, 'text')
    await L.adaptadorHttpN8n(helpers, { verificarCertificado: true })({ url: 'x', corpoBinario: new Uint8Array([1]) })
    assert.equal(pedido.skipSslCertificateValidation, false)
    assert.equal(pedido.headers['Content-Type'], 'application/octet-stream')
  })
})
