// Roda com `node --test n8n` e com `npm test` (vitest). Inclui teste ponta a ponta contra o mock da Zig (n8n/mocks).
import assert from 'node:assert/strict'
import {
  dataValida, somarDias, diasDoPeriodo, periodoZig, urlZig, requisicaoZig, lojasParaSincronizar, planejarChamadas, itensDaResposta,
  novoResumoZig, acumularResumo, registrarFalha, resumoFinalZig, importarZig, lerPaginadoZig, ENDPOINTS_ZIG,
} from './zig.mjs'
import { requisitarComRetentativa, chamarRpc, criarHttpFetch } from '../../comum/lib/supabase.mjs'
import { iniciarMocks } from '../../mocks/servidor.mjs'
import { iniciarSupabaseFalso } from '../../mocks/supabase-falso.mjs'

const { test } = process.env.VITEST ? await import('vitest') : await import('node:test')

const CONFIG = {
  integracao_id: 'a0000000-0000-4000-8000-000000000101', empresa_id: 'a0000000-0000-4000-8000-00000000000a', tipo: 'zig', nome: 'Zig', ativa: true,
  parametros: { rede: 'rede-mock', dias_retroativos: 2 }, segredos: { token: 'token-mock' }, cursor: {}, fuso: 'America/Sao_Paulo',
  virada_dia: '05:00:00', dia_trabalho_atual: '2026-10-06', lojas: [],
}

test('datas e período', () => {
  assert.equal(dataValida('2026-02-29'), false)
  assert.equal(dataValida('2028-02-29'), true)
  assert.equal(somarDias('2026-12-31', 1), '2027-01-01')
  assert.deepEqual(diasDoPeriodo('2026-09-30', '2026-10-02'), ['2026-09-30', '2026-10-01', '2026-10-02'])
  assert.throws(() => diasDoPeriodo('2026-10-02', '2026-10-01'), /inválido/)
  assert.throws(() => diasDoPeriodo('2026-01-01', '2026-03-01'), /máximo de 31/)
  // padrão: [hoje − dias_retroativos, hoje]
  assert.deepEqual(periodoZig({}, CONFIG), { inicio: '2026-10-04', fim: '2026-10-06', dias: ['2026-10-04', '2026-10-05', '2026-10-06'], truncado: false })
  // manual com data_inicio ignora dias_retroativos; fim no futuro é limitado ao dia atual
  const m = periodoZig({ data_inicio: '2026-09-20', data_fim: '2026-10-30' }, CONFIG)
  assert.equal(m.inicio, '2026-09-20')
  assert.equal(m.fim, '2026-10-06')
  assert.equal(m.dias.length, 17)
  // só data_inicio → até hoje
  assert.equal(periodoZig({ data_inicio: '2026-10-01' }, CONFIG).fim, '2026-10-06')
  // mais de 31 dias → os 31 últimos
  const t = periodoZig({ data_inicio: '2026-07-01', data_fim: '2026-10-06' }, CONFIG)
  assert.equal(t.truncado, true)
  assert.equal(t.dias.length, 31)
  assert.equal(t.inicio, '2026-09-06')
  assert.equal(periodoZig({}, { ...CONFIG, parametros: { rede: 'r' } }).inicio, '2026-10-04')
  assert.equal(periodoZig({}, { ...CONFIG, parametros: { rede: 'r', dias_retroativos: 0 } }).dias.length, 1)
  assert.throws(() => periodoZig({ data_inicio: 'ontem' }, CONFIG), /inválida/)
})

test('URLs e cabeçalho (Authorization sem Bearer)', () => {
  assert.equal(urlZig('https://api.zigcore.com.br/integration/', '/erp/lojas', { rede: 'r 1' }), 'https://api.zigcore.com.br/integration/erp/lojas?rede=r%201')
  const r = requisicaoZig(undefined, 'tok', '/erp/faturamento', { dtinicio: '2026-10-05', dtfim: '2026-10-05', loja: 'L1' })
  assert.equal(r.url, 'https://api.zigcore.com.br/integration/erp/faturamento?dtinicio=2026-10-05&dtfim=2026-10-05&loja=L1')
  assert.equal(r.headers.Authorization, 'tok')
  assert.equal(r.method, 'GET')
})

test('lojas, plano e resumo', () => {
  assert.deepEqual(lojasParaSincronizar([{ id: 1, name: 'A' }, { id: '2', name: 'B' }, { id: 1 }, {}], [{ loja_id_externo: '2', sincronizar: false }]), ['1'])
  const plano = planejarChamadas(['L1', 'L2'], ['2026-10-05', '2026-10-06'])
  assert.equal(plano.length, 2 * 2 * ENDPOINTS_ZIG.length)
  assert.deepEqual(plano[0], { loja: 'L1', dia: '2026-10-05', endpoint: 'saida_produtos', caminho: '/erp/saida-produtos', rpc: 'ingestao_zig_saida_produtos' })
  assert.deepEqual(itensDaResposta(null), [])
  assert.deepEqual(itensDaResposta({ data: [1] }), [1])
  assert.throws(() => itensDaResposta({ x: 1 }), /inesperada/)
  const r = novoResumoZig()
  acumularResumo(r, 'faturamento', { lidos: 4, gravados: 4, ignorados: 0, removidos: 3 })
  assert.equal(resumoFinalZig(r).status, 'sucesso')
  registrarFalha(r, { loja: 'L', dia: 'd', endpoint: 'compradores', erro: 'x' })
  const f = resumoFinalZig(r)
  assert.equal(f.status, 'parcial')
  assert.equal(f.lidos, 4)
  assert.equal(f.detalhes.por_endpoint.faturamento.removidos, 3)
  assert.match(f.erro, /1 de 2 chamadas falharam/)
  const so = novoResumoZig()
  registrarFalha(so, { loja: 'L', dia: 'd', endpoint: 'compradores', erro: 'x' })
  assert.equal(resumoFinalZig(so).status, 'erro')
})

test('importarZig com dependências falsas: falha de um endpoint vira parcial', async () => {
  const rpcs = []
  const deps = {
    pausaMs: 0,
    requisitar: async (req) => {
      if (req.url.includes('/erp/lojas')) return { status: 200, corpo: [{ id: 'L1', name: 'Loja' }], tentativas: 1 }
      if (req.url.includes('compradores') && req.url.includes('2026-10-05')) { const e = new Error('HTTP 500'); e.status = 500; e.tentativas = 3; throw e }
      return { status: 200, corpo: [{ a: 1 }, { a: 2 }], tentativas: 1 }
    },
    rpc: async (nome, args) => { rpcs.push({ nome, args }); return { lidos: args.p_itens ? args.p_itens.length : 1, gravados: args.p_itens ? args.p_itens.length : 1, ignorados: 0, removidos: 0 } },
  }
  const r = await importarZig(CONFIG, { data_inicio: '2026-10-05', data_fim: '2026-10-06' }, deps)
  assert.equal(r.status, 'parcial')
  assert.equal(r.tentativas, 3)
  assert.equal(r.detalhes.lojas, 1)
  assert.equal(r.detalhes.dias, 2)
  assert.equal(r.detalhes.por_endpoint.compradores.falhas, 1)
  assert.equal(r.lidos, 7 * 2)
  assert.equal(rpcs[0].nome, 'ingestao_zig_lojas')
  assert.deepEqual(rpcs[1].args, { p_integracao: CONFIG.integracao_id, p_loja: 'L1', p_data: '2026-10-05', p_itens: [{ a: 1 }, { a: 2 }] })
  await assert.rejects(importarZig({ ...CONFIG, segredos: {} }, {}, deps), /Token da Zig/)
  await assert.rejects(importarZig({ ...CONFIG, tipo: 'controlid_rep' }, {}, deps), /incompatível/)
})

test('ponta a ponta: libs (HTTP real) × mock da Zig × Supabase falso', async () => {
  const anterior = process.env.MOCK_AGORA
  process.env.MOCK_AGORA = '2026-10-06T12:00:00-03:00'
  const mocks = await iniciarMocks({ zig: 0, acesso: 0, rep: 0 })
  const sb = await iniciarSupabaseFalso({ chave: 'k' })
  try {
    const http = criarHttpFetch(fetch)
    const cfg = { url: sb.url, chave: 'k' }
    const base = `http://127.0.0.1:${mocks.portas.zig}/integration`
    const esperas = []
    const deps = {
      baseUrl: base, pausaMs: 1, esperaMs: 5,
      dormir: async (ms) => { esperas.push(ms) },
      requisitar: (req, op) => requisitarComRetentativa(http, req, op),
      rpc: (nome, args) => chamarRpc(http, cfg, nome, args),
    }
    // agenda 2 respostas 429 no faturamento → a lib espera (Retry-After 1 s) e consegue na 3ª
    await fetch(`${base.replace('/integration', '')}/__mock/falhas`, { method: 'POST', body: JSON.stringify({ caminho: '/integration/erp/faturamento', status: 429, vezes: 2 }) })
    const r = await importarZig(CONFIG, { data_inicio: '2026-10-04', data_fim: '2026-10-05' }, deps)
    assert.equal(r.status, 'sucesso', r.erro)
    assert.equal(r.tentativas, 3)
    assert.ok(esperas.includes(1000), 'respeitou Retry-After')
    assert.equal(r.detalhes.lojas, 1)
    assert.equal(r.detalhes.dias, 2)
    const nomes = sb.chamadas.map((c) => c.rpc)
    assert.equal(nomes[0], 'ingestao_zig_lojas')
    assert.deepEqual(sb.chamadas[0].args.p_lojas, [{ id: 'loja-1', name: 'Bossa Nova Salão' }])
    assert.equal(nomes.filter((n) => n === 'ingestao_zig_saida_produtos').length, 2)
    const saida = sb.chamadas.find((c) => c.rpc === 'ingestao_zig_saida_produtos')
    assert.equal(saida.args.p_loja, 'loja-1')
    assert.equal(saida.args.p_data, '2026-10-04')
    const tips = saida.args.p_itens.filter((i) => i.type === 'Tip')
    assert.ok(tips.length > 0, 'tem serviço (Tip)')
    assert.ok(saida.args.p_itens.every((i) => typeof i.unitValue === 'number'), 'centavos sem transformar')
    // faturamento do dia = Σ itens (sem desconto) + Tips
    const fat = sb.chamadas.find((c) => c.rpc === 'ingestao_zig_faturamento' && c.args.p_data === '2026-10-04').args.p_itens.reduce((s, x) => s + x.value, 0)
    const itens = saida.args.p_itens.reduce((s, x) => s + x.unitValue * x.count - (x.discountValue || 0), 0)
    assert.equal(fat, itens)
    // idempotência: reimportar o mesmo dia manda exatamente o mesmo lote (a RPC substitui o dia)
    const antes = sb.chamadas.length
    await importarZig(CONFIG, { data_inicio: '2026-10-04', data_fim: '2026-10-04' }, deps)
    const segunda = sb.chamadas.slice(antes).find((c) => c.rpc === 'ingestao_zig_saida_produtos')
    assert.deepEqual(segunda.args, saida.args)

    // rede com loja sempre 500 e loja sempre 429 → tudo falha → erro
    const ruim = await importarZig({ ...CONFIG, parametros: { rede: 'rede-erro', dias_retroativos: 0 } }, {}, deps)
    assert.equal(ruim.status, 'erro')
    assert.equal(ruim.detalhes.por_endpoint.saida_produtos.falhas, 2)
    assert.match(ruim.erro, /8 de 8 chamadas falharam/)
    // token errado → 401 sem retentativa → a execução inteira falha
    await assert.rejects(importarZig({ ...CONFIG, segredos: { token: 'x' } }, {}, deps), /HTTP 401/)

    // paginação (/erp/invoice) — 5 por página no mock
    const notas = await lerPaginadoZig((req) => requisitarComRetentativa(http, req, { dormir: async () => {} }), base, 'token-mock', '/erp/invoice', { dtinicio: '2026-10-05', dtfim: '2026-10-05', loja: 'loja-1' }, { pageSize: 5 })
    const total = (await (await fetch(`${base}/erp/invoice?dtinicio=2026-10-05&dtfim=2026-10-05&loja=loja-1`, { headers: { Authorization: 'token-mock' } })).json()).total
    assert.equal(notas.length, total)
    assert.equal(new Set(notas.map((n) => n.invoiceId)).size, total)
  } finally {
    await sb.fechar()
    await mocks.fechar()
    if (anterior === undefined) delete process.env.MOCK_AGORA
    else process.env.MOCK_AGORA = anterior
  }
})
