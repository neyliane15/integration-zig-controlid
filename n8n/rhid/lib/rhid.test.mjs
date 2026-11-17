// Roda com `node --test "n8n/**/*.test.mjs"` e com `npm test` (vitest). Funções puras + ponta a ponta (HTTP real) contra o
// mock do RHiD (n8n/mocks/rhid.mjs, porta aleatória) e um Supabase falso, e o JSON do workflow "MDG · RHiD · Importar" no simulador.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import {
  validarConfigRhid, planoRhid, requisicaoLoginRhid, tokenDoLoginRhid, registrosRhid, textoAfdRhid, empresasRhid, alvosRhid,
  janelaRhid, requisicaoAfdRhid, abrirSessaoRhid, importarPessoasRhid, importarBatidasRhid, juntarSaidasRhid, RHID_BASE_PADRAO,
  cpfRhid, deveImportarHorariosRhid, janelaHorariosRhid, diasApuracaoRhid, importarHorariosRhid,
} from './rhid.mjs'
import { lerAfd, resumoAfd } from '../../controlid/lib/afd.mjs'
import { requisitarComRetentativa, criarHttpFetch } from '../../comum/lib/supabase.mjs'
import { iniciarMocks, RHID_MOCK } from '../../mocks/servidor.mjs'
import { iniciarSupabaseFalso } from '../../mocks/supabase-falso.mjs'
import { executarWorkflow } from '../../mocks/simulador-n8n.mjs'

const { test, before, after } = process.env.VITEST ? await import('vitest') : await import('node:test')
const beforeAll = process.env.VITEST ? (await import('vitest')).beforeAll : before
const afterAll = process.env.VITEST ? (await import('vitest')).afterAll : after

const N8N = join(dirname(fileURLToPath(import.meta.url)), '../..')
const EMPRESA = 'a0000000-0000-4000-8000-00000000000a'
const RHID_ID = 'a0000000-0000-4000-8000-000000000105'
const AMOSTRA = readFileSync(join(N8N, 'mocks/dados/rhid-afd-671-rep-p-amostra.txt'), 'latin1')

let mocks, base, hoje
const configMock = (extra = {}, cursor = {}) => ({
  integracao_id: RHID_ID, empresa_id: EMPRESA, tipo: 'rhid', ativa: true, dia_trabalho_atual: hoje, cursor,
  parametros: { equipamentos: [], incluir_rep_p: true, dias_retroativos: 7, importar_pessoas: true, url_base: base, ...extra },
  segredos: { email: RHID_MOCK.email, senha: RHID_MOCK.senha },
})
const http = criarHttpFetch(fetch)
const requisitar = (req, opcoes) => requisitarComRetentativa(http, req, { ...opcoes, esperaMs: 5 })

beforeAll(async () => {
  mocks = await iniciarMocks({ zig: 0, acesso: 0, rep: 0, rhid: 0 })
  base = `http://127.0.0.1:${mocks.portas.rhid}${RHID_MOCK.base}`
  hoje = (await (await fetch(`http://127.0.0.1:${mocks.portas.rhid}/__mock/estado`)).json()).dia_trabalho
})
afterAll(async () => {
  if (mocks) await mocks.fechar()
})

test('configuração: tipo, credenciais e URL base (padrão oficial)', () => {
  assert.throws(() => validarConfigRhid({ tipo: 'tagme' }), /incompatível/)
  assert.throws(() => validarConfigRhid({ tipo: 'rhid', segredos: { email: 'a@b' } }), /e-mail e senha/)
  assert.equal(validarConfigRhid({ tipo: 'rhid', segredos: { email: 'a', senha: 'b' }, parametros: {} }), RHID_BASE_PADRAO)
  assert.equal(validarConfigRhid({ tipo: 'rhid', segredos: { email: 'a', senha: 'b' }, parametros: {} }, 'http://x/v2/api.svc/'), 'http://x/v2/api.svc')
  assert.deepEqual(planoRhid({ escopo: 'tudo' }, { parametros: {} }), { pessoas: true, batidas: true })
  assert.deepEqual(planoRhid({ escopo: 'tudo' }, { parametros: { importar_pessoas: false } }), { pessoas: false, batidas: true })
  assert.deepEqual(planoRhid({ escopo: 'funcionarios' }, null), { pessoas: true, batidas: false })
  assert.deepEqual(planoRhid({ escopo: 'batidas' }, null), { pessoas: false, batidas: true })
})

test('login: corpo {email, password, domain?}; token; erros claros sem ecoar a senha', () => {
  const r = requisicaoLoginRhid('http://x', { email: ' a@b ', senha: 's', dominio: '' })
  assert.deepEqual([r.method, r.url, r.corpo], ['POST', 'http://x/login', { email: 'a@b', password: 's' }])
  assert.equal(requisicaoLoginRhid('http://x', { email: 'a', senha: 's', dominio: 'macaw' }).corpo.domain, 'macaw')
  assert.equal(tokenDoLoginRhid({ accessToken: 'abc' }), 'abc')
  assert.equal(tokenDoLoginRhid('{"accessToken":"xyz"}'), 'xyz')
  assert.throws(() => tokenDoLoginRhid({ expiredPassword: true, accessToken: 'a' }), /expirou/)
  assert.throws(() => tokenDoLoginRhid({ isPerson: true, accessToken: 'a' }), /colaborador/)
  assert.throws(() => tokenDoLoginRhid({ error: 'Invalid credentials.' }), /sem token/)
})

test('respostas: records, AFD como string JSON, empresas e equipamentos alvo', () => {
  assert.deepEqual(registrosRhid({ totalRecords: 1, records: [{ id: 1 }] }, 'x'), [{ id: 1 }])
  assert.deepEqual(registrosRhid([{ id: 2 }], 'x'), [{ id: 2 }])
  assert.throws(() => registrosRhid({ code: 400, error: 'Bad request' }, 'pessoas'), /Bad request/)
  assert.equal(textoAfdRhid(JSON.stringify('0001\r\n0002\r\n')), '0001\r\n0002\r\n')
  assert.equal(textoAfdRhid('0001\r\n'), '0001\r\n')
  assert.throws(() => textoAfdRhid('{"error":"Data range bigger than 90 days"}'), /90 days/)
  assert.deepEqual(empresasRhid([{ idCompany: 2 }, { idCompany: 1 }, { idCompany: 2 }], [{ linkedCompanyId: 3 }]), [1, 2, 3])
  const devs = [{ id: 55, name: 'REP MACAW', model: 1 }, { id: 56, name: 'iDFace', model: 3 }, { id: 57, name: 'REP-P app', model: 5 }]
  assert.deepEqual(alvosRhid(devs, {}, [1]).map((a) => [a.chave, a.rota, a.automatico]),
    [['55', 'afd', false], ['99000001', 'afd', true], ['c99000001', 'coletor', true]])
  assert.deepEqual(alvosRhid(devs, { incluir_rep_p: false }, [1]).map((a) => a.chave), ['55'])
  assert.deepEqual(alvosRhid(devs, { equipamentos: ['55', 99000002, { id: 'x' }] }, [1]).map((a) => [a.chave, a.nome]),
    [['55', 'REP MACAW'], ['99000002', 'REP-P (empresa 2)'], ['c99000002', 'REP-P (empresa 2) · coletor']])
})

test('janela: cursor (NSR + 1, 90 dias), retroativo, período pedido; nunca passa de 90 dias', () => {
  const c = { dia_trabalho_atual: '2026-10-06', parametros: { dias_retroativos: 7 } }
  assert.deepEqual(janelaRhid({}, c, 120), { dataIni: '2026-07-10', dataFinal: '2026-10-07', nsrInicial: 121, modo: 'cursor' })
  assert.deepEqual(janelaRhid({}, c, undefined), { dataIni: '2026-09-29', dataFinal: '2026-10-07', nsrInicial: null, modo: 'retroativo' })
  assert.deepEqual(janelaRhid({ data_inicio: '2026-10-01', data_fim: '2026-10-03' }, c, 120),
    { dataIni: '2026-10-01', dataFinal: '2026-10-04', nsrInicial: null, modo: 'periodo' })
  assert.equal(janelaRhid({}, { ...c, parametros: { dias_retroativos: 500 } }).dataIni, '2026-07-10')
  assert.throws(() => janelaRhid({ data_inicio: '2026-10-05', data_fim: '2026-10-01' }, c), /inválido/)
  const r = requisicaoAfdRhid('http://x', 'tk', { id: 99000001, rota: 'coletor' }, janelaRhid({}, c, 5), 50000)
  assert.equal(r.url, 'http://x/report/afd_coletor_marcacao/download671?idEquipamento=99000001&dataIni=2026-07-10&dataFinal=2026-10-07&nsrInicial=6&limit=50000')
  assert.equal(r.headers.Authorization, 'Bearer tk')
  assert.equal(r.texto, true)
})

test('amostra real do RHiD (REP-P, latin-1, tipos 1/2/5, assinatura): sem marcações, nada quebra', () => {
  const l = lerAfd(AMOSTRA)
  assert.equal(l.marcacoes.length, 0)
  assert.equal(l.ignoradas.length, 0)
  assert.ok(l.outros_registros['5'] >= 7)
})

test('ponta a ponta (HTTP): login → pessoas → equipamentos → AFD REP + REP-P + coletor → lotes; cursor; 401 renova o login', async () => {
  const gravadas = []
  const rpc = async (nome, args) => {
    if (nome === 'ingestao_rhid_pessoas') return { lidos: args.p_pessoas.length, gravados: args.p_pessoas.length, ignorados: 0 }
    if (nome === 'ingestao_rhid_batidas') {
      gravadas.push(...args.p_marcacoes.map((m) => ({ ...m, equip: args.p_equipamento })))
      return { lidos: args.p_marcacoes.length, gravados: args.p_marcacoes.length, ignorados: 0, duplicados: 0, ultimo_nsr: Math.max(...args.p_marcacoes.map((m) => m.nsr)) }
    }
    throw new Error(`rpc inesperada ${nome}`)
  }
  const config = configMock()
  const sessao = await abrirSessaoRhid(config, { requisitar })
  const p = await importarPessoasRhid(config, sessao, { rpc })
  assert.equal(p.status, 'sucesso')
  assert.equal(p.lidos, 6, '5 funcionários demo + 1 só no RHiD')
  const b = await importarBatidasRhid(config, {}, sessao, { rpc, lerAfd, resumoAfd, tamanhoLote: 7 })
  assert.equal(b.status, 'sucesso', b.erro)
  const porEquip = Object.groupBy(gravadas, (m) => m.equip)
  assert.deepEqual(Object.keys(porEquip).sort(), ['55', '99000001', 'c99000001'])
  assert.ok(porEquip['55'].length > 10 && porEquip['55'].every((m) => /T\d{2}:\d{2}:00-03:00$/.test(m.instante) && m.cpf.length === 11))
  assert.equal(porEquip['99000001'].length, porEquip.c99000001.length, 'coletor repete as do REP-P (o banco deduplica)')
  assert.ok(porEquip['99000001'].every((m) => m.cpf === '71428793860' && m.nsr >= 350), 'REP-P: tipo 7 da cozinha')
  assert.equal(b.lidos, gravadas.length)
  const eq55 = b.detalhes.equipamentos.find((e) => e.chave === '55')
  assert.equal(eq55.janela.modo, 'retroativo')
  assert.ok(eq55.paginas >= 1 && eq55.ultimo_nsr > 0)
  assert.equal(sessao.logins, 1)
  assert.ok(!JSON.stringify([p, b]).includes(RHID_MOCK.senha) && !JSON.stringify([p, b]).includes('rhid-token-'), 'nem senha nem token nos detalhes')

  // segunda rodada com cursor: nada novo; o token expira no meio → novo login transparente
  await fetch(`http://127.0.0.1:${mocks.portas.rhid}/__mock/rhid/expirar`, { method: 'POST' })
  gravadas.length = 0
  const cursor = Object.fromEntries(b.detalhes.equipamentos.map((e) => [e.chave, e.ultimo_nsr]))
  const b2 = await importarBatidasRhid(configMock({}, { nsr_por_equipamento: cursor }), {}, sessao, { rpc, lerAfd })
  assert.equal(b2.status, 'sucesso', b2.erro)
  assert.equal(gravadas.length, 0)
  assert.equal(sessao.logins, 2)
  assert.ok(b2.detalhes.equipamentos.every((e) => e.janela.modo === 'cursor' && e.janela.nsrInicial === cursor[e.chave] + 1))

  // limite pequeno: pagina pelo NSR
  gravadas.length = 0
  const b3 = await importarBatidasRhid(configMock({ equipamentos: [55], limite_afd: 5 }), {}, sessao, { rpc, lerAfd })
  assert.equal(b3.status, 'sucesso', b3.erro)
  assert.equal(new Set(gravadas.map((m) => m.nsr)).size, porEquip['55'].length)
  assert.ok(b3.detalhes.equipamentos[0].paginas > 2)

  // equipamento explícito inexistente → erro; automático (REP-P) inexistente → só aviso
  await assert.rejects(importarBatidasRhid(configMock({ equipamentos: [77] }), {}, sessao, { rpc, lerAfd }), /Equipamento 77.*HTTP 400/)
  const b4 = await importarBatidasRhid(configMock({ equipamentos: [55, 77] }), {}, sessao, { rpc, lerAfd })
  assert.equal(b4.status, 'parcial')
  assert.match(b4.erro, /Equipamento 77/)
})

test('horários: apuração do RHiD (formato real) → previsto, folga, feriado, horários; janela e intervalo', () => {
  const real = JSON.stringify([
    { date: '2026-11-01T00:00:00', strHorarioContratualSimples: '08:00-13:00\r\n13:30-15:50', horasUteis: 440, folga: false, isHoliday: 0, holiday: null, saldoBancoCredDeb: -326 },
    { date: '2026-11-02T00:00:00', strHorarioContratualSimples: '', horasUteis: 0, folga: false, isHoliday: 1, holiday: { name: 'Finados', folga: false }, saldoBancoCredDeb: 622 },
    { date: '2026-11-03T00:00:00', strHorarioContratualSimples: '08:00-13:00\r\n13:30-15:50', horasUteis: 440, folga: true, isHoliday: 0, holiday: null, saldoBancoCredDeb: 0 },
    { dateTimeStr: '20261104', strHorarioContratualSimples: '15:00-17:00\r\n17:30-22:50', horasUteis: 440, folga: false },
    { date: 'lixo' }, null,
  ])
  const d = diasApuracaoRhid(JSON.stringify(real), '04567891230')
  assert.deepEqual(d.map((x) => [x.data, x.previsto_minutos, x.folga, x.feriado, x.horarios.join(' '), x.saldo_minutos]), [
    ['2026-11-01', 440, false, null, '08:00 13:00 13:30 15:50', -326],
    ['2026-11-02', 0, false, 'Finados', '', 622],
    ['2026-11-03', 0, true, null, '08:00 13:00 13:30 15:50', 0],
    ['2026-11-04', 440, false, null, '15:00 17:00 17:30 22:50', null],
  ])
  assert.ok(d.every((x) => x.cpf === '04567891230'))
  assert.throws(() => diasApuracaoRhid('{"error":"Sem permissão"}', 'x'), /Sem permissão/)
  assert.equal(cpfRhid(4567891230), '04567891230')
  assert.equal(cpfRhid(0), null)
  const cfg = (cursor, p = {}) => ({ dia_trabalho_atual: '2026-11-17', cursor, parametros: p })
  const agora = Date.parse('2026-11-17T15:00:00Z')
  assert.equal(deveImportarHorariosRhid({ gatilho: 'agendado' }, cfg({}), agora), true, 'nunca rodou')
  assert.equal(deveImportarHorariosRhid({ gatilho: 'agendado' }, cfg({ horarios_em: '2026-11-17T14:30:00Z' }), agora), false, 'rodou há 30 min')
  assert.equal(deveImportarHorariosRhid({ gatilho: 'agendado' }, cfg({ horarios_em: '2026-11-17T13:59:00Z' }), agora), true)
  assert.equal(deveImportarHorariosRhid({ gatilho: 'manual' }, cfg({ horarios_em: '2026-11-17T14:59:00Z' }), agora), true, 'manual sempre')
  assert.equal(deveImportarHorariosRhid({ gatilho: 'manual' }, cfg({}, { importar_horarios: false }), agora), false)
  assert.deepEqual(janelaHorariosRhid({}, cfg({})), { dataIni: '2026-10-08', dataFinal: '2026-11-17' })
  assert.deepEqual(janelaHorariosRhid({ data_inicio: '2026-11-01', data_fim: '2026-12-31' }, cfg({})), { dataIni: '2026-11-01', dataFinal: '2026-11-17' })
  assert.deepEqual(janelaHorariosRhid({ data_inicio: '2026-01-01' }, cfg({})).dataIni, '2026-08-20', '≤ 90 dias')
})

test('horários ponta a ponta (HTTP): só CPFs ligados, uma apuração por pessoa, lotes', async () => {
  const lotes = []
  const rpc = async (nome, args) => {
    if (nome === 'ingestao_rhid_vinculados') return ['52998224725', '99999999999']
    if (nome === 'ingestao_rhid_horarios') { lotes.push(args.p_dias); return { gravados: args.p_dias.length, iguais: 0, ignorados: 0, funcionarios_reapurados: 1 } }
    throw new Error(`rpc inesperada ${nome}`)
  }
  const config = configMock()
  const sessao = await abrirSessaoRhid(config, { requisitar })
  const h = await importarHorariosRhid(config, { data_inicio: '2026-11-09', data_fim: '2026-11-16' }, sessao, { rpc, tamanhoLote: 5 })
  assert.equal(h.status, 'sucesso', h.erro)
  assert.equal(h.lidos, 8)
  assert.deepEqual(lotes.map((l) => l.length), [5, 3])
  const dias = lotes.flat()
  assert.ok(dias.every((x) => x.cpf === '52998224725'))
  assert.deepEqual(dias.filter((x) => x.previsto_minutos === 0).map((x) => [x.data, x.folga, x.feriado]),
    [['2026-11-15', false, 'Proclamação da República']], '15/11 (domingo) é feriado: previsto 0')
  assert.deepEqual(dias.find((x) => x.data === '2026-11-09').horarios, ['08:00', '13:00', '13:30', '15:50'])
  assert.match(h.detalhes.avisos.join(' '), /…99 ligado, mas não está nas pessoas do RHiD/)
})

test('credenciais erradas: erro do login sem a senha na mensagem', async () => {
  const c = { ...configMock(), segredos: { email: RHID_MOCK.email, senha: 'errada-123' } }
  await assert.rejects(abrirSessaoRhid(c, { requisitar }), (e) => /RHiD login: HTTP 400.*Invalid credentials/.test(e.message) && !e.message.includes('errada-123'))
})

test('juntar saídas: pior status, somas e ids', () => {
  assert.deepEqual(juntarSaidasRhid([{ execucao_ids: ['a'], status: 'sucesso', lidos: 2, gravados: 2, ignorados: 0, erro: null },
    { execucao_ids: ['b'], status: 'parcial', lidos: 3, gravados: 1, ignorados: 2, erro: 'x' }]),
  { execucao_ids: ['a', 'b'], status: 'parcial', lidos: 5, gravados: 3, ignorados: 2, erro: 'x' })
  assert.equal(juntarSaidasRhid([]).status, 'erro')
})

test('workflow "MDG · RHiD · Importar" no simulador + despacho pela fila e pelo Agendador', async () => {
  const fila = [
    { solicitacao_id: 's-r', empresa_id: EMPRESA, integracao_id: RHID_ID, integracao_tipo: 'rhid', escopo: 'tudo', parametros: {} },
    { solicitacao_id: 's-b', empresa_id: EMPRESA, integracao_id: RHID_ID, integracao_tipo: 'rhid', escopo: 'batidas', parametros: {} },
    { solicitacao_id: 's-v', empresa_id: EMPRESA, integracao_id: RHID_ID, integracao_tipo: 'rhid', escopo: 'vendas', parametros: {} },
  ]
  const sb = await iniciarSupabaseFalso({ chave: 'k', rpcs: {
    ingestao_integracao_config: () => configMock({ url_base: '' }),
    ingestao_sync_pegar_solicitacoes: () => fila.splice(0),
    ingestao_integracoes_ativas: () => [{ integracao_id: RHID_ID, empresa_id: EMPRESA, tipo: 'rhid', nome: 'RHiD', intervalo_minutos: 60, ultima_execucao_em: null }],
    ingestao_rhid_pessoas: (a) => ({ lidos: a.p_pessoas.length, gravados: a.p_pessoas.length, ignorados: 0 }),
    ingestao_rhid_batidas: (a) => ({ lidos: a.p_marcacoes.length, gravados: a.p_marcacoes.length, ignorados: 0, duplicados: 0, ultimo_nsr: Math.max(...a.p_marcacoes.map((m) => m.nsr)) }),
    ingestao_rhid_vinculados: () => ['52998224725'],
    ingestao_rhid_horarios: (a) => ({ lidos: a.p_dias.length, gravados: a.p_dias.length, iguais: 0, ignorados: 0, funcionarios_reapurados: 1 }),
  } })
  try {
    const ler = (rel) => JSON.parse(readFileSync(join(N8N, rel), 'utf8'))
    const ctx = { env: { SUPABASE_URL: sb.url, SUPABASE_SERVICE_ROLE_KEY: 'k', MDG_WF_RHID_IMPORTAR: 'wf-rhid', RHID_BASE_URL: base }, workflows: { 'wf-rhid': ler('rhid/workflows/rhid-importar.json') }, emails: [], http: [] }
    const r = await executarWorkflow(ler('comum/workflows/sincronizar-agora.json'), [], ctx)
    assert.equal(r.erro, null, r.erro && r.erro.message)
    const concl = Object.fromEntries(sb.chamadas.filter((c) => c.rpc === 'ingestao_sync_concluir_solicitacao').map((c) => [c.args.p_solicitacao, c.args]))
    assert.equal(concl['s-r'].p_status, 'concluida', concl['s-r'].p_mensagem)
    assert.equal(concl['s-b'].p_status, 'concluida', concl['s-b'].p_mensagem)
    assert.match(concl['s-v'].p_mensagem, /não se aplica a integração do tipo "rhid"/)
    const ini = sb.chamadas.filter((c) => c.rpc === 'ingestao_sync_iniciar').map((c) => [c.args.p_tipo, c.args.p_workflow])
    assert.deepEqual(ini.map((x) => x[0]), ['rhid_pessoas', 'rhid_batidas', 'rhid_horarios', 'rhid_batidas', 'rhid_horarios'])
    assert.ok(ini.every((x) => x[1] === 'MDG · RHiD · Importar'))
    const fins = sb.chamadas.filter((c) => c.rpc === 'ingestao_sync_finalizar').map((c) => c.args)
    assert.ok(fins.every((f) => f.p_status === 'sucesso'), JSON.stringify(fins.map((f) => f.p_erro)))
    assert.ok(!JSON.stringify(sb.chamadas).includes('rhid-token-'), 'token não vai para o banco')
    // agendador
    const n = sb.chamadas.length
    const ag = await executarWorkflow(ler('comum/workflows/agendador.json'), [], ctx)
    assert.equal(ag.erro, null, ag.erro && ag.erro.message)
    assert.deepEqual([ag.saida[0].json.total, ag.saida[0].json.erros], [1, 0])
    assert.deepEqual(sb.chamadas.slice(n).filter((c) => c.rpc === 'ingestao_sync_iniciar').map((c) => [c.args.p_tipo, c.args.p_gatilho]),
      [['rhid_pessoas', 'agendado'], ['rhid_batidas', 'agendado'], ['rhid_horarios', 'agendado']], 'sem cursor.horarios_em: roda')
    // sem MDG_WF_RHID_IMPORTAR → pedido em erro citando a variável
    fila.push({ solicitacao_id: 's-x', empresa_id: EMPRESA, integracao_id: RHID_ID, integracao_tipo: 'rhid', escopo: 'tudo', parametros: {} })
    await executarWorkflow(ler('comum/workflows/sincronizar-agora.json'), [], { ...ctx, env: { ...ctx.env, MDG_WF_RHID_IMPORTAR: '' } })
    assert.match(sb.chamadas.filter((c) => c.rpc === 'ingestao_sync_concluir_solicitacao').at(-1).args.p_mensagem, /MDG_WF_RHID_IMPORTAR/)
    // senha errada → as duas execuções fecham com erro do login
    const sb2 = await iniciarSupabaseFalso({ chave: 'k', rpcs: { ingestao_integracao_config: () => ({ ...configMock({ url_base: '' }), segredos: { email: RHID_MOCK.email, senha: 'x' } }) } })
    try {
      const r2 = await executarWorkflow(ler('rhid/workflows/rhid-importar.json'), [{ json: { integracao_id: RHID_ID, escopo: 'tudo', gatilho: 'manual' } }], { ...ctx, env: { ...ctx.env, SUPABASE_URL: sb2.url } })
      assert.equal(r2.saida[0].json.status, 'erro')
      assert.match(r2.saida[0].json.erro, /Invalid credentials/)
      assert.deepEqual(sb2.chamadas.filter((c) => c.rpc === 'ingestao_sync_finalizar').map((c) => c.args.p_status), ['erro', 'erro'])
    } finally {
      await sb2.fechar()
    }
  } finally {
    await sb.fechar()
  }
})
