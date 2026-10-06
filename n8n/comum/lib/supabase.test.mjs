// Roda com `node --test "n8n/**/*.test.mjs"` e com `npm test` (vitest).
import assert from 'node:assert/strict'
import {
  lerVariavel, configSupabase, montarChamadaRpc, deveRetentar, lerRetryAfter, esperaAntesDaProxima, requisitarComRetentativa,
  chamarRpc, criarHttpFetch, subfluxosDe, planejarDespacho, normalizarSaida, consolidarSolicitacoes, comExecucao, urlSegura, selecionar, envioAtivo, precisaConfigParaDespacho,
} from './supabase.mjs'
import { iniciarSupabaseFalso } from '../../mocks/supabase-falso.mjs'

const { test } = process.env.VITEST ? await import('vitest') : await import('node:test')

const IDS = { CONTROLID_USUARIOS: 'wf-u', CONTROLID_BATIDAS: 'wf-b', CONTROLID_EXPORTAR: 'wf-e', ZIG_IMPORTAR: 'wf-z', EXPORTAR_FECHAMENTO: 'wf-f' }
const sol = (x) => ({ solicitacao_id: 's1', empresa_id: 'e1', integracao_id: 'i1', integracao_tipo: 'zig', escopo: 'tudo', data_inicio: null, data_fim: null, parametros: {}, ...x })

/** http falso: devolve as respostas da fila, na ordem. */
function httpFila(respostas) {
  const reqs = []
  const http = async (req) => {
    reqs.push(req)
    const r = respostas.shift()
    if (r instanceof Error) throw r
    return { headers: {}, ...r }
  }
  return { http, reqs }
}
const semEspera = { dormir: async () => {} }

test('lerVariavel: ordem das fontes, fonte bloqueada e vazios', () => {
  const bloqueada = () => { throw new Error('access to env vars denied') }
  assert.equal(lerVariavel('X', [bloqueada, () => ({ X: ' v ' })]), 'v')
  assert.equal(lerVariavel('X', [() => ({ X: '' }), { X: 'b' }]), 'b')
  assert.equal(lerVariavel('X', [() => ({})], 'padrão'), 'padrão')
  assert.deepEqual(configSupabase([{ SUPABASE_URL: 'https://p.supabase.co/', SUPABASE_SERVICE_ROLE_KEY: 'k' }]), { url: 'https://p.supabase.co', chave: 'k' })
  assert.throws(() => configSupabase([{}]), /SUPABASE_URL/)
})

test('montarChamadaRpc: URL, cabeçalhos e corpo sem undefined', () => {
  const r = montarChamadaRpc({ url: 'https://p.co', chave: 'k' }, 'ingestao_sync_iniciar', { p_tipo: 'zig_importar', p_x: undefined, p_y: null })
  assert.equal(r.method, 'POST')
  assert.equal(r.url, 'https://p.co/rest/v1/rpc/ingestao_sync_iniciar')
  assert.equal(r.headers.apikey, 'k')
  assert.equal(r.headers.Authorization, 'Bearer k')
  assert.deepEqual(r.corpo, { p_tipo: 'zig_importar', p_y: null })
  assert.throws(() => montarChamadaRpc({ url: 'u', chave: 'k' }, 'x; drop', {}), /inválido/)
})

test('deveRetentar, Retry-After e backoff', () => {
  assert.equal(deveRetentar(429), true)
  assert.equal(deveRetentar(500), true)
  assert.equal(deveRetentar(503), true)
  assert.equal(deveRetentar(null), true)
  assert.equal(deveRetentar(400), false)
  assert.equal(deveRetentar(401), false)
  assert.equal(deveRetentar(404), false)
  assert.equal(lerRetryAfter({ 'retry-after': '3' }), 3000)
  assert.equal(lerRetryAfter({ 'retry-after': new Date(10000).toUTCString() }, 4000), 6000)
  assert.equal(lerRetryAfter({}), null)
  assert.equal(esperaAntesDaProxima(1, { esperaMs: 10000 }), 10000)
  assert.equal(esperaAntesDaProxima(2, { esperaMs: 10000 }), 20000)
  assert.equal(esperaAntesDaProxima(3, { esperaMs: 10000, maxEsperaMs: 25000 }), 25000)
  assert.equal(esperaAntesDaProxima(1, { esperaMs: 1000, retryAfterMs: 7000 }), 7000)
  assert.equal(urlSegura('http://x/a.fcgi?session=abc&b=1'), 'http://x/a.fcgi?session=***&b=1')
})

test('requisitarComRetentativa: 429 → 500 → 200 com backoff', async () => {
  const { http, reqs } = httpFila([{ status: 429, headers: { 'retry-after': '2' } }, { status: 500 }, { status: 200, corpo: [1] }])
  const esperas = []
  const r = await requisitarComRetentativa(http, { method: 'GET', url: 'http://z' }, { tentativas: 3, esperaMs: 1000, dormir: async (ms) => esperas.push(ms) })
  assert.equal(r.tentativas, 3)
  assert.deepEqual(r.corpo, [1])
  assert.equal(reqs.length, 3)
  assert.deepEqual(esperas, [2000, 2000])
})

test('requisitarComRetentativa: falha de rede esgota; 4xx não retenta', async () => {
  const a = httpFila([new Error('ECONNREFUSED'), new Error('ECONNREFUSED'), new Error('ECONNREFUSED')])
  await assert.rejects(requisitarComRetentativa(a.http, { method: 'GET', url: 'http://z' }, { ...semEspera, rotulo: 'Zig' }), (e) => {
    assert.equal(e.tentativas, 3)
    assert.match(e.message, /Zig: ECONNREFUSED \(após 3 tentativas\)/)
    return true
  })
  const b = httpFila([{ status: 400, corpo: { message: 'Loja não encontrada' } }])
  await assert.rejects(requisitarComRetentativa(b.http, { method: 'POST', url: 'http://z' }, { ...semEspera, rotulo: 'RPC x' }), (e) => {
    assert.equal(e.status, 400)
    assert.equal(e.tentativas, 1)
    assert.match(e.message, /RPC x: HTTP 400 — Loja não encontrada/)
    return true
  })
  assert.equal(b.reqs.length, 1)
})

test('despacho: tabela tipo × escopo (§12.3 + adendo de envio)', () => {
  assert.deepEqual(subfluxosDe('zig', 'tudo'), ['ZIG_IMPORTAR'])
  assert.deepEqual(subfluxosDe('zig', 'vendas'), ['ZIG_IMPORTAR'])
  assert.equal(subfluxosDe('zig', 'batidas'), null)
  assert.deepEqual(subfluxosDe('controlid_acesso', 'tudo', false), ['CONTROLID_USUARIOS', 'CONTROLID_BATIDAS'])
  assert.deepEqual(subfluxosDe('controlid_acesso', 'tudo', true), ['CONTROLID_USUARIOS', 'CONTROLID_EXPORTAR', 'CONTROLID_BATIDAS'])
  assert.deepEqual(subfluxosDe('controlid_rep', 'tudo', true), ['CONTROLID_USUARIOS', 'CONTROLID_EXPORTAR', 'CONTROLID_BATIDAS'])
  assert.deepEqual(subfluxosDe('controlid_rep', 'exportar_funcionarios'), ['CONTROLID_EXPORTAR'])
  assert.deepEqual(subfluxosDe('controlid_acesso', 'funcionarios'), ['CONTROLID_USUARIOS'])
  assert.deepEqual(subfluxosDe('controlid_rep', 'batidas'), ['CONTROLID_BATIDAS'])
  assert.equal(subfluxosDe('controlid_acesso', 'vendas'), null)
  assert.deepEqual(subfluxosDe(null, 'exportar_fechamento'), ['EXPORTAR_FECHAMENTO'])
})

test('planejarDespacho: passos com entrada do subfluxo, datas repassadas', () => {
  const p = planejarDespacho(sol({ integracao_tipo: 'controlid_acesso', data_inicio: '2026-09-01', data_fim: '2026-09-10' }), IDS, { envioAtivo: true })
  assert.equal(p.length, 3)
  assert.deepEqual(p.map((x) => x._despacho.workflow_id), ['wf-u', 'wf-e', 'wf-b'])
  assert.deepEqual(p.map((x) => x._despacho.ordem), [1, 2, 3])
  assert.equal(p[0].gatilho, 'manual')
  assert.equal(p[0].data_inicio, '2026-09-01')
  assert.equal(p[0].data_fim, '2026-09-10')
  assert.equal(p[0].tipo, 'controlid_acesso')
  assert.equal(p[0]._despacho.workflow_nome, 'MDG · Control iD · Importar usuários')

  const ag = planejarDespacho({ integracao_id: 'i9', empresa_id: 'e1', tipo: 'zig', escopo: 'tudo' }, IDS, { gatilho: 'agendado' })
  assert.equal(ag[0].gatilho, 'agendado')
  assert.equal(ag[0].solicitacao_id, null)
  assert.equal(ag[0]._despacho.chave, 'i9|tudo')

  assert.equal(planejarDespacho(sol({ integracao_tipo: null, integracao_id: null, escopo: 'apurar_ponto' }), IDS)[0]._despacho.acao, 'apurar_ponto')
  const fe = planejarDespacho(sol({ integracao_tipo: null, escopo: 'exportar_fechamento', parametros: { fechamento_id: 'f1' } }), IDS)
  assert.equal(fe[0]._despacho.workflow_id, 'wf-f')
  assert.equal(fe[0].parametros.fechamento_id, 'f1')
  assert.equal(planejarDespacho(sol({ escopo: 'exportar_fechamento' }), IDS)[0]._despacho.acao, 'invalido')
  assert.match(planejarDespacho(sol({ escopo: 'batidas' }), IDS)[0]._despacho.erro, /não se aplica/)
  const semId = planejarDespacho(sol(), {})[0]._despacho
  assert.equal(semId.acao, 'invalido')
  assert.equal(semId.tipo_execucao, 'zig_importar')
  assert.match(semId.erro, /MDG_WF_ZIG_IMPORTAR/)
  // um subfluxo sem id → solicitação inteira inválida, um passo só
  const parcial = planejarDespacho(sol({ integracao_tipo: 'controlid_rep' }), { ...IDS, CONTROLID_BATIDAS: '' })
  assert.equal(parcial.length, 1)
  assert.match(parcial[0]._despacho.erro, /MDG_WF_CONTROLID_BATIDAS/)
  assert.equal(envioAtivo({ parametros: { envio: { ativo: true } } }), true)
  assert.equal(envioAtivo({ parametros: {} }), false)
  assert.equal(precisaConfigParaDespacho(sol({ integracao_tipo: 'controlid_acesso' })), true)
  assert.equal(precisaConfigParaDespacho(sol({ integracao_tipo: 'controlid_acesso', escopo: 'batidas' })), false)
  assert.equal(precisaConfigParaDespacho(sol()), false)
})

test('normalizarSaida e consolidarSolicitacoes', () => {
  assert.equal(normalizarSaida({ error: { message: 'boom' } }).erro, 'boom')
  assert.equal(normalizarSaida({}).status, 'erro')
  const ok = normalizarSaida({ execucao_ids: ['x1'], status: 'sucesso', lidos: 3, gravados: 2, ignorados: 1, erro: null })
  assert.deepEqual(ok, { status: 'sucesso', lidos: 3, gravados: 2, ignorados: 1, erro: null, execucao_ids: ['x1'] })
  const passos = [
    { _despacho: { solicitacao_id: 's1', ordem: 2, workflow_nome: 'B' }, resultado: { status: 'erro', erro: 'falhou', execucao_ids: ['x2'] } },
    { _despacho: { solicitacao_id: 's1', ordem: 1, workflow_nome: 'A' }, resultado: ok },
    { _despacho: { solicitacao_id: 's2', ordem: 1 }, resultado: { ...ok, status: 'parcial', execucao_ids: ['x3'] } },
    { _despacho: { solicitacao_id: null, ordem: 1 }, resultado: ok },
  ]
  const c = consolidarSolicitacoes(passos)
  assert.equal(c.length, 2)
  assert.deepEqual(c[0], { solicitacao_id: 's1', status: 'erro', mensagem: 'B: falhou', execucao_id: 'x2' })
  assert.equal(c[1].status, 'concluida')
  assert.match(c[1].mensagem, /3 lidos, 2 gravados, 1 ignorados \(1 parcial\)/)
})

test('ponta a ponta (HTTP real contra Supabase falso): comExecucao abre e fecha sync_execucoes', async () => {
  const sb = await iniciarSupabaseFalso({ chave: 'k1', rpcs: { ingestao_apurar_ponto: (a) => ({ empresas: 1, funcionarios: 5, dias: 3, recebido: a }) } })
  try {
    const http = criarHttpFetch(fetch)
    const cfg = { url: sb.url, chave: 'k1' }
    const saida = await comExecucao(http, cfg, { tipo: 'apurar_ponto', gatilho: 'manual', workflow: 'MDG · Sincronizar agora (fila)', empresa_id: 'e1', solicitacao_id: 's1', n8n_execution_id: 42 }, async () => {
      const r = await chamarRpc(http, cfg, 'ingestao_apurar_ponto', { p_empresa: 'e1' })
      return { status: 'sucesso', lidos: r.funcionarios, gravados: r.dias, detalhes: r }
    })
    assert.equal(saida.status, 'sucesso')
    assert.equal(saida.gravados, 3)
    assert.equal(saida.execucao_ids.length, 1)
    assert.deepEqual(sb.chamadas.map((c) => c.rpc), ['ingestao_sync_iniciar', 'ingestao_apurar_ponto', 'ingestao_sync_finalizar'])
    assert.equal(sb.chamadas[0].args.p_n8n_execution_id, '42')
    assert.equal(sb.chamadas[0].args.p_gatilho, 'manual')
    assert.equal(sb.chamadas[2].args.p_execucao, saida.execucao_ids[0])
    assert.equal(sb.chamadas[2].args.p_status, 'sucesso')

    // erro no trabalho → fecha com erro e não lança
    const erro = await comExecucao(http, cfg, { tipo: 'apurar_ponto', gatilho: 'agendado', workflow: 'w' }, async () => {
      await chamarRpc(http, cfg, 'nao_existe', {}, semEspera)
    })
    assert.equal(erro.status, 'erro')
    assert.match(erro.erro, /HTTP 404/)
    assert.equal(sb.chamadas.at(-1).args.p_status, 'erro')

    // chave errada → 401 sem retentativa
    await assert.rejects(chamarRpc(http, { url: sb.url, chave: 'errada' }, 'ingestao_tarefas_gerar', {}, semEspera), /HTTP 401/)
    // leitura de tabela
    const linhas = await selecionar(http, cfg, 'sync_execucoes', { n8n_execution_id: 'eq.7', select: 'id' })
    assert.deepEqual(linhas, [])
    assert.deepEqual(sb.chamadas.at(-1).filtros, { n8n_execution_id: 'eq.7', select: 'id' })
  } finally {
    await sb.fechar()
  }
})
