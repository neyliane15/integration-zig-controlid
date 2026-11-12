// Roda com `node --test "n8n/**/*.test.mjs"` e com `npm test` (vitest). Inclui ponta a ponta (HTTP real) contra o mock da Tagme
// (n8n/mocks/servidor.mjs, porta própria) e um Supabase falso, e o JSON do workflow "MDG · Tagme · Importar" no simulador.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import {
  periodoTagme, lerCaminho, primeiroValor, mapeamentoTagme, listaDaResposta, normalizarStatusTagme, interpretarDataHora,
  normalizarReservaTagme, formatarDataTagme, janelasConsulta, parametrosConsulta, cabecalhosTagme, urlTagme, requisicaoTagme,
  validarConfigTagme, importarTagme, TAGME_STATUS,
} from './tagme.mjs'
import { requisitarComRetentativa, criarHttpFetch, chamarRpc } from '../../comum/lib/supabase.mjs'
import { iniciarMocks, TAGME_MOCK } from '../../mocks/servidor.mjs'
import { iniciarSupabaseFalso } from '../../mocks/supabase-falso.mjs'
import { executarWorkflow } from '../../mocks/simulador-n8n.mjs'

const { test, before, after } = process.env.VITEST ? await import('vitest') : await import('node:test')
const beforeAll = process.env.VITEST ? (await import('vitest')).beforeAll : before
const afterAll = process.env.VITEST ? (await import('vitest')).afterAll : after

const N8N = join(dirname(fileURLToPath(import.meta.url)), '../..')
const EMPRESA = 'a0000000-0000-4000-8000-00000000000a'
const TAGME_ID = 'a0000000-0000-4000-8000-000000000104'

/** Configuração como viria de `ingestao_integracao_config` para o mock (o mapeamento é o que o suporte preencheria). */
const configMock = (base, extra = {}) => ({
  integracao_id: TAGME_ID, empresa_id: EMPRESA, tipo: 'tagme', ativa: true, dia_trabalho_atual: '2026-10-06', cursor: {},
  parametros: {
    url_base: base, caminho: TAGME_MOCK.caminho, metodo: 'GET', dias_retroativos: 1, dias_a_frente: 6,
    consulta: { modo: 'periodo', param_inicio: 'start_date', param_fim: 'end_date', formato_data: 'AAAA-MM-DD' },
    paginacao: { param_pagina: 'page', param_tamanho: 'per_page', tamanho: 10, caminho_total_paginas: 'meta.total_pages' },
    mapeamento: { lista: 'data.reservations', id: '_id', data_hora: 'scheduled_at', nome: 'customer.name', telefone: 'customer.phone', email: 'customer.email', pessoas: 'party_size', status: 'status', observacao: 'notes' },
    ...extra,
  },
  segredos: { token: TAGME_MOCK.token },
})

test('período: padrão [hoje − retro, hoje + futuros], manual, truncado e inválido', () => {
  const c = { dia_trabalho_atual: '2026-10-06', parametros: {} }
  const p = periodoTagme({}, c)
  assert.equal(p.inicio, '2026-10-05')
  assert.equal(p.fim, '2026-10-13')
  assert.equal(p.dias.length, 9)
  assert.deepEqual(periodoTagme({ data_inicio: '2026-10-01', data_fim: '2026-10-03' }, c).dias, ['2026-10-01', '2026-10-02', '2026-10-03'])
  assert.equal(periodoTagme({ data_inicio: '2026-10-01' }, c).fim, '2026-10-01')
  const t = periodoTagme({ data_inicio: '2026-01-01', data_fim: '2026-12-31' }, c)
  assert.equal(t.truncado, true)
  assert.equal(t.dias.length, 62)
  assert.throws(() => periodoTagme({ data_inicio: '2026-10-05', data_fim: '2026-10-01' }, c), /inválido/)
  assert.throws(() => periodoTagme({ data_inicio: 'ontem' }, c), /inválida/)
  assert.throws(() => periodoTagme({}, { parametros: {} }), /dia_trabalho_atual/)
})

test('caminhos, mapeamento padrão + configurado, lista da resposta', () => {
  const o = { a: { b: [{ c: 1 }] }, x: '' }
  assert.equal(lerCaminho(o, 'a.b.0.c'), 1)
  assert.equal(lerCaminho(o, 'a.z.c'), undefined)
  assert.equal(lerCaminho(o, ''), o)
  assert.equal(primeiroValor(o, ['x', 'a.b.0.c']), 1)
  const m = mapeamentoTagme({ mapeamento: { id: 'codigo', status_map: { 'Na Mesa': 'sentada' } } })
  assert.equal(m.id, 'codigo')
  assert.ok(Array.isArray(m.nome) && m.nome.includes('customer.name'))
  assert.equal(m.status_map.na_mesa, 'sentada')
  assert.deepEqual(listaDaResposta({ data: { reservations: [1, 2] } }, m.lista), [1, 2])
  assert.deepEqual(listaDaResposta([3], m.lista), [3])
  assert.deepEqual(listaDaResposta(null, m.lista), [])
  assert.throws(() => listaDaResposta({ x: 1 }, 'data.reservas', true), /ajuste parametros.mapeamento.lista/)
  assert.throws(() => listaDaResposta([1], 'data.reservas', true), /sem a lista/)
  assert.throws(() => listaDaResposta('<html>login</html>', m.lista), /não é JSON/)
})

test('status, datas e horas', () => {
  assert.deepEqual(TAGME_STATUS, ['confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu'])
  assert.equal(normalizarStatusTagme('CONFIRMED'), 'confirmada')
  assert.equal(normalizarStatusTagme('Cancelled'), 'cancelada')
  assert.equal(normalizarStatusTagme('NO_SHOW'), 'nao_compareceu')
  assert.equal(normalizarStatusTagme('Seated'), 'sentada')
  assert.equal(normalizarStatusTagme('Concluída'), 'concluida')
  assert.equal(normalizarStatusTagme('xpto'), 'pendente')
  assert.equal(normalizarStatusTagme(null), 'confirmada')
  assert.deepEqual(interpretarDataHora('2026-10-06'), { data: '2026-10-06', hora: null })
  assert.deepEqual(interpretarDataHora('2026-10-06T20:30:00-03:00'), { data: '2026-10-06', hora: '20:30' })
  assert.deepEqual(interpretarDataHora('2026-10-06T23:30:00Z'), { data: '2026-10-06', hora: '20:30' })
  assert.deepEqual(interpretarDataHora('2026-10-07T01:00:00.000Z'), { data: '2026-10-06', hora: '22:00' })
  assert.deepEqual(interpretarDataHora('2026-10-06 19:45:00'), { data: '2026-10-06', hora: '19:45' })
  assert.deepEqual(interpretarDataHora('06/10/2026 21:00'), { data: '2026-10-06', hora: '21:00' })
  assert.deepEqual(interpretarDataHora(Date.parse('2026-10-06T20:00:00-03:00')), { data: '2026-10-06', hora: '20:00' })
  assert.deepEqual(interpretarDataHora('1791334800'), interpretarDataHora(1791334800000))
  assert.deepEqual(interpretarDataHora('9h30'), { data: null, hora: '09:30' })
  assert.deepEqual(interpretarDataHora('31/02/2026'), { data: null, hora: null })
  assert.equal(formatarDataTagme('2026-10-06', 'DD/MM/AAAA'), '06/10/2026')
  assert.equal(formatarDataTagme('2026-10-06', 'AAAAMMDD'), '20261006')
  assert.equal(formatarDataTagme('2026-10-06', 'iso', true), '2026-10-06T23:59:59-03:00')
  assert.equal(formatarDataTagme('2026-10-06', 'epoch'), String(Date.parse('2026-10-06T00:00:00-03:00') / 1000))
  assert.throws(() => formatarDataTagme('2026-10-06', 'mm-dd'), /desconhecido/)
})

test('normalizar reserva (padrão e configurado), sem id/data → null', () => {
  const padrao = mapeamentoTagme({})
  const r = normalizarReservaTagme({ id: 7, date: '2026-10-06', time: '20:00', customer: { name: ' Ana ', phone: '11 9999' }, party_size: '4', status: 'confirmed', table: { name: '12' }, area: 'Varanda', notes: 'Aniversário' }, padrao)
  assert.deepEqual({ ...r, bruto: undefined }, {
    id_externo: '7', data: '2026-10-06', hora: '20:00', nome: 'Ana', telefone: '11 9999', email: null, pessoas: 4, status: 'confirmada',
    observacao: 'Aniversário', area: 'Varanda', mesa: '12', origem: 'tagme', bruto: undefined,
  })
  const m = mapeamentoTagme({ mapeamento: { id: 'codigo', data_hora: 'quando', nome: 'cli.nm', pessoas: 'qtd', status: 'sit', status_map: { ok: 'confirmada' } } })
  const r2 = normalizarReservaTagme({ codigo: 'X', quando: '06/10/2026 19:30', cli: { nm: 'Bia' }, qtd: 0, sit: 'OK' }, m)
  assert.equal(r2.data, '2026-10-06')
  assert.equal(r2.hora, '19:30')
  assert.equal(r2.nome, 'Bia')
  assert.equal(r2.pessoas, null)
  assert.equal(r2.status, 'confirmada')
  assert.equal(normalizarReservaTagme({ date: '2026-10-06' }, padrao), null)
  assert.equal(normalizarReservaTagme({ id: 1 }, padrao), null)
  assert.equal(normalizarReservaTagme(null, padrao), null)
})

test('requisição: GET com query, POST com corpo, autenticação configurável, URL absoluta no caminho', () => {
  const janelas = janelasConsulta({ inicio: '2026-10-05', fim: '2026-10-06', dias: ['2026-10-05', '2026-10-06'] }, { modo: 'dia' })
  assert.deepEqual(janelas, [{ inicio: '2026-10-05', fim: '2026-10-05' }, { inicio: '2026-10-06', fim: '2026-10-06' }])
  assert.deepEqual(parametrosConsulta({ inicio: '2026-10-05', fim: '2026-10-05' }, { modo: 'dia', param_dia: 'dia', formato_data: 'DD/MM/AAAA', extras: { unidade: 9 } }), { unidade: 9, dia: '05/10/2026' })
  assert.deepEqual(parametrosConsulta({ inicio: '2026-10-05', fim: '2026-10-06' }, {}, { param_pagina: 'p', param_tamanho: 'n', tamanho: 50 }, 2), { start_date: '2026-10-05', end_date: '2026-10-06', p: 2, n: 50 })
  assert.deepEqual(cabecalhosTagme({}, { token: 't' }), { Accept: 'application/json', Authorization: 'Bearer t' })
  assert.deepEqual(cabecalhosTagme({ autenticacao: { cabecalho: 'Authorization', prefixo: 'Bearer ' } }, { token: 't' }), { Accept: 'application/json', Authorization: 'Bearer t' })
  assert.deepEqual(cabecalhosTagme({ autenticacao: { cabecalho: 'Cookie', prefixo: '' } }, { token: 'sessao=abc' }), { Accept: 'application/json', Cookie: 'sessao=abc' })
  assert.deepEqual(cabecalhosTagme({ autenticacao: { cabecalho: 'x-access-token', prefixo: '', cabecalho_cliente_id: 'x-client-id' } }, { token: 't', cliente_id: 'c1' }),
    { Accept: 'application/json', 'x-access-token': 't', 'x-client-id': 'c1' })
  assert.deepEqual(cabecalhosTagme({ autenticacao: { modo: 'basic' } }, { cliente_id: 'usuário', cliente_segredo: 's3' }),
    { Accept: 'application/json', Authorization: `Basic ${Buffer.from('usuário:s3').toString('base64')}` })
  assert.equal(urlTagme('https://h', '/v1/{restaurante_id}/reservas', { a: 1 }, 'R 9'), 'https://h/v1/R%209/reservas?a=1')
  assert.deepEqual(parametrosConsulta({ inicio: '2026-10-05', fim: '2026-10-05' }, { param_restaurante: 'restaurant_id' }, null, 1, 77), { restaurant_id: '77', start_date: '2026-10-05', end_date: '2026-10-05' })
  assert.equal(urlTagme('https://waitlist.tagme.com.br/', 'api/r', { a: '1 2', b: null }), 'https://waitlist.tagme.com.br/api/r?a=1%202')
  assert.equal(urlTagme('x', 'https://outra/api?v=1', { a: 1 }), 'https://outra/api?v=1&a=1')
  const g = requisicaoTagme('https://h', { caminho: '/r' }, { token: 't' }, { start_date: '2026-10-05' })
  assert.equal(g.url, 'https://h/r?start_date=2026-10-05')
  const p = requisicaoTagme('https://h', { caminho: '/r', metodo: 'post' }, { token: 't' }, { start_date: '2026-10-05' })
  assert.equal(p.method, 'POST')
  assert.deepEqual(p.corpo, { start_date: '2026-10-05' })
  assert.equal(p.headers['Content-Type'], 'application/json')
  assert.throws(() => requisicaoTagme('https://h', { caminho: '/r', metodo: 'PUT' }, {}, {}), /não suportado/)
})

test('configuração: tipo, endpoint, URL base e credencial obrigatórios (mensagens para leigo)', () => {
  assert.throws(() => validarConfigTagme({ tipo: 'zig' }), /incompatível/)
  assert.throws(() => validarConfigTagme({ tipo: 'tagme', parametros: {}, segredos: { token: 't' } }), /Endpoint de reservas da Tagme não configurado.*CSV/)
  assert.throws(() => validarConfigTagme({ tipo: 'tagme', parametros: { caminho: '/r' }, segredos: { token: 't' } }), /URL base.*waitlist\.tagme\.com\.br/)
  assert.throws(() => validarConfigTagme({ tipo: 'tagme', parametros: { caminho: '/r', url_base: 'https://h' }, segredos: {} }), /segredos: token/)
  assert.throws(() => validarConfigTagme({ tipo: 'tagme', parametros: { caminho: '/r', url_base: 'https://h', autenticacao: { modo: 'basic' } }, segredos: { token: 't' } }), /cliente_id e cliente_segredo/)
  assert.throws(() => validarConfigTagme({ tipo: 'tagme', parametros: { caminho: '/{restaurante_id}/r', url_base: 'https://h' }, segredos: { token: 't' } }), /restaurante_id/)
  assert.deepEqual(validarConfigTagme({ tipo: 'tagme', parametros: { caminho: '/r' }, segredos: { token: 't' } }, 'https://var'), { base: 'https://var', caminho: '/r' })
  assert.deepEqual(validarConfigTagme({ tipo: 'tagme', parametros: { caminho: '/r', url_base: 'https://p' }, segredos: { token: 't' } }, 'https://var'), { base: 'https://p', caminho: '/r' })
})

test('importarTagme (transporte falso): paginação por tamanho, dedup, fora do período, mapeamento errado não apaga nada', async () => {
  const paginas = [
    { data: [{ id: 1, date: '2026-10-05' }, { id: 2, date: '2026-10-06' }] },
    { data: [{ id: 2, date: '2026-10-06', status: 'seated' }, { id: 3, date: '2026-12-01' }] },
    { data: [{ semId: true, date: '2026-10-06' }] },
  ]
  const reqs = []
  const rpcs = []
  const config = { integracao_id: 'i', tipo: 'tagme', dia_trabalho_atual: '2026-10-06', parametros: { url_base: 'https://h', caminho: '/r', dias_retroativos: 1, dias_a_frente: 1, paginacao: { param_pagina: 'page', tamanho: 2 } }, segredos: { token: 't' } }
  const r = await importarTagme(config, {}, {
    pausaMs: 0,
    requisitar: async (req) => { reqs.push(req.url); return { status: 200, corpo: paginas[reqs.length - 1], tentativas: reqs.length === 2 ? 2 : 1 } },
    rpc: async (nome, args) => { rpcs.push([nome, args]); return { lidos: args.p_itens.length, gravados: args.p_itens.length, ignorados: 0, removidos: 0 } },
  })
  assert.equal(reqs.length, 3)
  assert.match(reqs[0], /start_date=2026-10-05&end_date=2026-10-07&page=1$/)
  assert.equal(rpcs.length, 1)
  assert.equal(rpcs[0][0], 'ingestao_reservas')
  assert.deepEqual([rpcs[0][1].p_integracao, rpcs[0][1].p_inicio, rpcs[0][1].p_fim], ['i', '2026-10-05', '2026-10-07'])
  assert.deepEqual(rpcs[0][1].p_itens.map((i) => [i.id_externo, i.status]), [['1', 'confirmada'], ['2', 'sentada']])
  assert.equal(r.status, 'sucesso')
  assert.deepEqual([r.lidos, r.gravados, r.ignorados, r.tentativas], [5, 2, 3, 2])
  assert.deepEqual([r.detalhes.sem_id_ou_data, r.detalhes.fora_do_periodo, r.detalhes.repetidos], [1, 1, 1])

  // nenhuma reserva reconhecível → lança e NÃO chama a ingestão
  rpcs.length = 0
  await assert.rejects(importarTagme({ ...config, parametros: { ...config.parametros, paginacao: undefined } }, {}, {
    pausaMs: 0, requisitar: async () => ({ status: 200, corpo: [{ foo: 1, bar: 2 }] }), rpc: async (n, a) => rpcs.push([n, a]),
  }), /confira parametros.mapeamento \(campos de um item: foo, bar\)/)
  assert.equal(rpcs.length, 0)

  // itens recusados pelo banco (erros[] do §11.2) → parcial
  const pz = await importarTagme({ ...config, parametros: { ...config.parametros, paginacao: undefined } }, {}, {
    pausaMs: 0, requisitar: async () => ({ status: 200, corpo: [{ id: 1, date: '2026-10-06' }, { id: 2, date: '2026-10-06' }] }),
    rpc: async () => ({ lidos: 2, gravados: 1, ignorados: 1, erros: [{ indice: 0, motivo: 'informe o nome' }] }),
  })
  assert.equal(pz.status, 'parcial')
  assert.match(pz.erro, /1 reserva\(s\) recusada\(s\) pelo banco: #0: informe o nome/)

  // lista vazia é legítima (sem reservas no período) → envia [] e avisa
  const v = await importarTagme({ ...config, parametros: { ...config.parametros, paginacao: undefined } }, {}, {
    pausaMs: 0, requisitar: async () => ({ status: 200, corpo: { data: [] } }), rpc: async (n, a) => ({ lidos: 0, gravados: 0, ignorados: 0, removidos: 3 }),
  })
  assert.equal(v.status, 'sucesso')
  assert.match(v.detalhes.aviso, /não devolveu reservas/)
})

// ------------------------------------------------------------------------------------------------ ponta a ponta (HTTP real)
let mocks, sb, base
beforeAll(async () => {
  mocks = await iniciarMocks({ zig: 0, acesso: 0, rep: 0, tagme: 0 })
  base = `http://127.0.0.1:${mocks.portas.tagme}`
  sb = await iniciarSupabaseFalso({ chave: 'k', rpcs: { ingestao_integracao_config: () => configMock(base) } })
})
afterAll(async () => {
  await sb?.fechar()
  await mocks?.fechar()
})

test('mock da Tagme: autenticação, período, paginação e POST', async () => {
  const get = (q, h = { Authorization: `Bearer ${TAGME_MOCK.token}` }) => fetch(`${base}${TAGME_MOCK.caminho}?${q}`, { headers: h })
  assert.equal((await get('start_date=2026-10-06&end_date=2026-10-06', {})).status, 401)
  assert.equal((await get('start_date=2026-10-06')).status, 400)
  const j = await (await get('start_date=2026-10-05&end_date=2026-10-06&per_page=5&page=2')).json()
  assert.deepEqual(j.meta, { page: 2, per_page: 5, total: 8, total_pages: 2 })
  assert.equal(j.data.reservations.length, 3)
  const a = await (await get('start_date=2026-10-06&end_date=2026-10-06')).json()
  const b = await (await fetch(`${base}${TAGME_MOCK.caminho}`, { method: 'POST', headers: { Authorization: `Bearer ${TAGME_MOCK.token}`, 'content-type': 'application/json' }, body: JSON.stringify({ start_date: '2026-10-06', end_date: '2026-10-06' }) })).json()
  assert.deepEqual(a, b, 'determinístico e igual em GET/POST')
})

test('ponta a ponta: mock Tagme (4 páginas) → Supabase falso, reimportação idêntica, 401 e 429 com retentativa', async () => {
  const http = criarHttpFetch(fetch)
  const cfg = { url: sb.url, chave: 'k' }
  const deps = {
    pausaMs: 0, dormir: async () => {},
    requisitar: (req, op) => requisitarComRetentativa(http, req, { ...op, dormir: async () => {} }),
    rpc: (nome, args) => chamarRpc(http, cfg, nome, args),
  }
  const n = sb.chamadas.length
  const r = await importarTagme(configMock(base), {}, deps)
  assert.equal(r.status, 'sucesso', r.erro)
  assert.equal(r.detalhes.chamadas, 4) // 8 dias × 4 = 32 reservas, 10 por página
  assert.equal(r.lidos, 32)
  assert.equal(r.gravados, 32)
  const envio = sb.chamadas.slice(n).find((c) => c.rpc === 'ingestao_reservas').args
  assert.deepEqual([envio.p_inicio, envio.p_fim, envio.p_itens.length], ['2026-10-05', '2026-10-12', 32])
  const it = envio.p_itens[0]
  assert.equal(it.id_externo, 'tg-20261005-1')
  assert.match(it.hora, /^(19|2[0-2]):(00|30)$/)
  assert.ok(it.nome && it.telefone && it.email && it.pessoas >= 2)
  assert.ok(envio.p_itens.every((i) => TAGME_STATUS.includes(i.status) && i.origem === 'tagme'))
  assert.ok(envio.p_itens.some((i) => i.status === 'cancelada') && envio.p_itens.some((i) => i.status === 'sentada'))
  assert.equal(envio.p_itens.find((i) => i.id_externo === 'tg-20261005-2').observacao, 'Aniversário; mesa perto da janela')
  // reimportar → mesmo envio
  const n2 = sb.chamadas.length
  await importarTagme(configMock(base), {}, deps)
  assert.deepEqual(sb.chamadas.slice(n2).find((c) => c.rpc === 'ingestao_reservas').args, envio)
  // token errado → 401 sem retentativa, nada enviado
  const n3 = sb.chamadas.length
  await assert.rejects(importarTagme({ ...configMock(base), segredos: { token: 'errado' } }, {}, deps), /HTTP 401/)
  assert.equal(sb.chamadas.slice(n3).filter((c) => c.rpc === 'ingestao_reservas').length, 0)
  // 429 duas vezes → retenta e conclui
  await fetch(`${base}/__mock/falhas`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ caminho: TAGME_MOCK.caminho, status: 429, vezes: 2 }) })
  const r4 = await importarTagme(configMock(base), { data_inicio: '2026-10-06', data_fim: '2026-10-06' }, deps)
  assert.equal(r4.status, 'sucesso')
  assert.equal(r4.tentativas, 3)
  assert.equal(r4.lidos, 4)
})

test('workflow "MDG · Tagme · Importar" no simulador: abre/fecha sync_execucoes tagme_importar; sem endpoint → erro claro', async () => {
  const wf = JSON.parse(readFileSync(join(N8N, 'tagme/workflows/tagme-importar.json'), 'utf8'))
  const ctx = { env: { SUPABASE_URL: sb.url, SUPABASE_SERVICE_ROLE_KEY: 'k' }, workflows: {}, emails: [], http: [] }
  const n = sb.chamadas.length
  const r = await executarWorkflow(wf, [{ json: { integracao_id: TAGME_ID, empresa_id: EMPRESA, tipo: 'tagme', escopo: 'reservas', gatilho: 'manual', solicitacao_id: 's1', data_inicio: null, data_fim: null, parametros: {} } }], ctx)
  assert.equal(r.erro, null, r.erro && r.erro.message)
  const s = r.saida[0].json
  assert.equal(s.status, 'sucesso', s.erro)
  assert.equal(s.gravados, 32)
  const rpcs = sb.chamadas.slice(n).filter((c) => c.rpc).map((c) => c.rpc)
  assert.deepEqual(rpcs, ['ingestao_integracao_config', 'ingestao_sync_iniciar', 'ingestao_reservas', 'ingestao_sync_finalizar'])
  const ini = sb.chamadas.slice(n).find((c) => c.rpc === 'ingestao_sync_iniciar').args
  assert.deepEqual([ini.p_tipo, ini.p_workflow, ini.p_gatilho, ini.p_periodo_inicio, ini.p_periodo_fim], ['tagme_importar', 'MDG · Tagme · Importar', 'manual', '2026-10-05', '2026-10-12'])

  // integração sem endpoint configurado: execução fechada com erro explicando o caminho (e o CSV)
  const sb2 = await iniciarSupabaseFalso({ chave: 'k', rpcs: { ingestao_integracao_config: () => ({ ...configMock(''), parametros: {} }) } })
  try {
    const r2 = await executarWorkflow(wf, [{ json: { integracao_id: TAGME_ID, gatilho: 'agendado' } }], { ...ctx, env: { SUPABASE_URL: sb2.url, SUPABASE_SERVICE_ROLE_KEY: 'k', TAGME_BASE_URL: 'https://waitlist.tagme.com.br' } })
    assert.equal(r2.saida[0].json.status, 'erro')
    assert.match(r2.saida[0].json.erro, /Endpoint de reservas da Tagme não configurado/)
    assert.equal(sb2.chamadas.find((c) => c.rpc === 'ingestao_sync_finalizar').args.p_status, 'erro')
  } finally {
    await sb2.fechar()
  }
})

test('fila "Sincronizar agora" e Agendador despacham o tipo tagme para o subfluxo', async () => {
  const fila = [{ solicitacao_id: 's-t', empresa_id: EMPRESA, integracao_id: TAGME_ID, integracao_tipo: 'tagme', escopo: 'reservas', data_inicio: '2026-10-06', data_fim: '2026-10-07', parametros: {} },
    { solicitacao_id: 's-v', empresa_id: EMPRESA, integracao_id: TAGME_ID, integracao_tipo: 'tagme', escopo: 'vendas', parametros: {} }]
  const sb3 = await iniciarSupabaseFalso({ chave: 'k', rpcs: {
    ingestao_integracao_config: () => configMock(base),
    ingestao_sync_pegar_solicitacoes: () => fila.splice(0),
    ingestao_integracoes_ativas: () => [{ integracao_id: TAGME_ID, empresa_id: EMPRESA, tipo: 'tagme', nome: 'Tagme', intervalo_minutos: 60, ultima_execucao_em: null }],
  } })
  try {
    const ler = (rel) => JSON.parse(readFileSync(join(N8N, rel), 'utf8'))
    const ctx = { env: { SUPABASE_URL: sb3.url, SUPABASE_SERVICE_ROLE_KEY: 'k', MDG_WF_TAGME_IMPORTAR: 'wf-tagme' }, workflows: { 'wf-tagme': ler('tagme/workflows/tagme-importar.json') }, emails: [], http: [] }
    const r = await executarWorkflow(ler('comum/workflows/sincronizar-agora.json'), [], ctx)
    assert.equal(r.erro, null, r.erro && r.erro.message)
    const concl = Object.fromEntries(sb3.chamadas.filter((c) => c.rpc === 'ingestao_sync_concluir_solicitacao').map((c) => [c.args.p_solicitacao, c.args]))
    assert.equal(concl['s-t'].p_status, 'concluida', concl['s-t'].p_mensagem)
    assert.match(concl['s-t'].p_mensagem, /^8 lidos, 8 gravados/)
    assert.equal(concl['s-v'].p_status, 'erro')
    assert.match(concl['s-v'].p_mensagem, /não se aplica a integração do tipo "tagme"/)
    const envio = sb3.chamadas.find((c) => c.rpc === 'ingestao_reservas').args
    assert.deepEqual([envio.p_inicio, envio.p_fim], ['2026-10-06', '2026-10-07'])
    // agendador
    const n = sb3.chamadas.length
    const ag = await executarWorkflow(ler('comum/workflows/agendador.json'), [], ctx)
    assert.equal(ag.erro, null, ag.erro && ag.erro.message)
    assert.deepEqual([ag.saida[0].json.total, ag.saida[0].json.erros], [1, 0])
    assert.equal(sb3.chamadas.slice(n).find((c) => c.rpc === 'ingestao_sync_iniciar').args.p_gatilho, 'agendado')
    // sem MDG_WF_TAGME_IMPORTAR → pedido em erro citando a variável
    fila.push({ solicitacao_id: 's-x', empresa_id: EMPRESA, integracao_id: TAGME_ID, integracao_tipo: 'tagme', escopo: 'tudo', parametros: {} })
    await executarWorkflow(ler('comum/workflows/sincronizar-agora.json'), [], { ...ctx, env: { ...ctx.env, MDG_WF_TAGME_IMPORTAR: '' } })
    assert.match(sb3.chamadas.filter((c) => c.rpc === 'ingestao_sync_concluir_solicitacao').at(-1).args.p_mensagem, /MDG_WF_TAGME_IMPORTAR/)
  } finally {
    await sb3.fechar()
  }
})
