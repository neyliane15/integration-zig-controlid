// Executa os workflows do n8n-2 (JSON de verdade, código de verdade dos nós Code) num simulador mínimo de N8N,
// contra os mocks da Zig e um Supabase falso. Roda com `node --test "n8n/**/*.test.mjs"` e com `npm test` (vitest).
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { executarWorkflow } from '../mocks/simulador-n8n.mjs'
import { iniciarMocks } from '../mocks/servidor.mjs'
import { iniciarSupabaseFalso } from '../mocks/supabase-falso.mjs'

const { test, before, after } = process.env.VITEST ? await import('vitest') : await import('node:test')
const beforeAll = process.env.VITEST ? (await import('vitest')).beforeAll : before
const afterAll = process.env.VITEST ? (await import('vitest')).afterAll : after

const N8N = join(dirname(fileURLToPath(import.meta.url)), '..')
const ler = (rel) => JSON.parse(readFileSync(join(N8N, rel), 'utf8'))
const WF = {
  zig: ler('zig/workflows/zig-importar.json'),
  fila: ler('comum/workflows/sincronizar-agora.json'),
  agendador: ler('comum/workflows/agendador.json'),
  rotina: ler('comum/workflows/rotina-diaria.json'),
  exportar: ler('comum/workflows/exportar-fechamento.json'),
  erros: ler('comum/workflows/erros.json'),
}
const EMPRESA = 'a0000000-0000-4000-8000-00000000000a'
const ZIG_ID = 'a0000000-0000-4000-8000-000000000101'
const ACESSO_ID = 'a0000000-0000-4000-8000-000000000102'

/** Subfluxo de Control iD de mentira (os de verdade são do n8n-1): devolve a saída do §12.3 e registra a entrada. */
const chamadasControlid = []
function stub(nome) {
  return {
    name: nome,
    nodes: [
      { name: 'Entrada', type: 'n8n-nodes-base.executeWorkflowTrigger', parameters: {} },
      { name: 'Fim', type: 'n8n-nodes-base.code', parameters: { jsCode: `globalThis.__chamadasControlid.push({ wf: ${JSON.stringify(nome)}, entrada: $input.first().json }); return [{ json: { execucao_ids: ['x-${nome}'], status: 'sucesso', lidos: 5, gravados: 5, ignorados: 0, erro: null } }]` } },
    ],
    connections: { Entrada: { main: [[{ node: 'Fim', type: 'main', index: 0 }]] } },
  }
}
globalThis.__chamadasControlid = chamadasControlid

let mocks, sb, ctx
const FECHAMENTO = {
  fechamento: { id: 'f1', empresa_nome: 'Bar Bossa Nova', titulo: 'Comissão 01/09 a 30/09/2026', data_inicio: '2026-09-01', data_fim: '2026-09-30', status: 'fechado',
    servico_zig_centavos: 1000000, servico_ajuste_centavos: -5000, servico_bruto_centavos: 995000, percentual_retencao: 20, retencao_centavos: 199000,
    base_distribuivel_centavos: 796000, valor_ponto_centavos: 20947.368421 },
  itens: [{ funcionario_nome: 'Ana Souza', cargo: 'Garçom', incluido: true, pontos: 10, dias_trabalhados: 30, pontos_efetivos: 10, valor_centavos: 796000 }],
}
let fila = []
let vencidas = []

beforeAll(async () => {
  process.env.MOCK_AGORA = '2026-10-06T12:00:00-03:00'
  mocks = await iniciarMocks({ zig: 0, acesso: 0, rep: 0 })
  sb = await iniciarSupabaseFalso({
    chave: 'k',
    rpcs: {
      ingestao_integracao_config: ({ p_integracao }) => p_integracao === ZIG_ID
        ? { integracao_id: ZIG_ID, empresa_id: EMPRESA, tipo: 'zig', ativa: true, parametros: { rede: 'rede-mock', dias_retroativos: 1 }, segredos: { token: 'token-mock' }, cursor: {}, dia_trabalho_atual: '2026-10-06', lojas: [] }
        : { integracao_id: p_integracao, empresa_id: EMPRESA, tipo: 'controlid_acesso', ativa: true, parametros: { envio: { ativo: true } }, segredos: {}, cursor: {}, dia_trabalho_atual: '2026-10-06' },
      ingestao_sync_pegar_solicitacoes: () => { const f = fila; fila = []; return f },
      ingestao_integracoes_ativas: () => vencidas,
      ingestao_fechamento_exportar: ({ p_fechamento }) => { if (p_fechamento !== 'f1') throw Object.assign(new Error('Fechamento não encontrado'), { status: 400 }); return FECHAMENTO },
    },
    tabelas: { sync_execucoes: (f) => (f.n8n_execution_id === 'eq.777' ? [{ id: 'exec-aberta' }] : []) },
  })
  ctx = {
    env: {
      SUPABASE_URL: sb.url, SUPABASE_SERVICE_ROLE_KEY: 'k', ZIG_BASE_URL: `http://127.0.0.1:${mocks.portas.zig}/integration`,
      MDG_WF_ZIG_IMPORTAR: 'wf-zig', MDG_WF_EXPORTAR_FECHAMENTO: 'wf-exp', MDG_WF_CONTROLID_USUARIOS: 'wf-u', MDG_WF_CONTROLID_BATIDAS: 'wf-b',
      MDG_WF_CONTROLID_EXPORTAR: 'wf-e', MDG_EMAIL_RELATORIOS: 'gerente@barbossanova.com.br',
    },
    workflows: { 'wf-zig': WF.zig, 'wf-exp': WF.exportar, 'wf-u': stub('usuarios'), 'wf-b': stub('batidas'), 'wf-e': stub('exportar') },
    emails: [],
    http: [],
  }
})
afterAll(async () => {
  await sb?.fechar()
  await mocks?.fechar()
  delete process.env.MOCK_AGORA
})

const rpcsDesde = (n) => sb.chamadas.slice(n).filter((c) => c.rpc).map((c) => c.rpc)

test('Zig · Importar: abre execução, importa 2 dias, fecha com sucesso e devolve a saída do §12.3', async () => {
  const n = sb.chamadas.length
  const r = await executarWorkflow(WF.zig, [{ json: { integracao_id: ZIG_ID, empresa_id: EMPRESA, tipo: 'zig', escopo: 'tudo', gatilho: 'manual', solicitacao_id: 's9', data_inicio: null, data_fim: null, parametros: {} } }], ctx)
  assert.equal(r.erro, null, r.erro && r.erro.message)
  const s = r.saida[0].json
  assert.equal(s.status, 'sucesso', s.erro)
  assert.equal(s.execucao_ids.length, 1)
  assert.ok(s.gravados > 0)
  const rpcs = rpcsDesde(n)
  assert.equal(rpcs[0], 'ingestao_integracao_config')
  assert.equal(rpcs[1], 'ingestao_sync_iniciar')
  assert.equal(rpcs.at(-1), 'ingestao_sync_finalizar')
  assert.equal(rpcs.filter((x) => x === 'ingestao_zig_faturamento').length, 2)
  const ini = sb.chamadas.slice(n).find((c) => c.rpc === 'ingestao_sync_iniciar').args
  assert.deepEqual([ini.p_tipo, ini.p_gatilho, ini.p_periodo_inicio, ini.p_periodo_fim, ini.p_solicitacao], ['zig_importar', 'manual', '2026-10-05', '2026-10-06', 's9'])
  assert.equal(ini.p_workflow, 'MDG · Zig · Importar')
  const fim = sb.chamadas.slice(n).find((c) => c.rpc === 'ingestao_sync_finalizar').args
  assert.equal(fim.p_detalhes.lojas, 1)
  assert.equal(fim.p_detalhes.dias, 2)
})

test('Zig · Importar: config inválida fecha a execução com erro (sem quebrar)', async () => {
  const n = sb.chamadas.length
  const r = await executarWorkflow(WF.zig, [{ json: { integracao_id: ACESSO_ID, empresa_id: EMPRESA, gatilho: 'agendado' } }], ctx)
  assert.equal(r.saida[0].json.status, 'erro')
  assert.match(r.saida[0].json.erro, /incompatível/)
  assert.equal(sb.chamadas.slice(n).find((c) => c.rpc === 'ingestao_sync_finalizar').args.p_status, 'erro')
})

test('Sincronizar agora: despacha zig, Control iD (com envio), apurar ponto, exportação e recusa inválida', async () => {
  chamadasControlid.length = 0
  ctx.emails.length = 0
  const n = sb.chamadas.length
  const base = { empresa_id: EMPRESA, data_inicio: null, data_fim: null, parametros: {} }
  fila = [
    { ...base, solicitacao_id: 's1', integracao_id: ZIG_ID, integracao_tipo: 'zig', escopo: 'vendas', data_inicio: '2026-10-06', data_fim: '2026-10-06' },
    { ...base, solicitacao_id: 's2', integracao_id: ACESSO_ID, integracao_tipo: 'controlid_acesso', escopo: 'tudo', data_inicio: '2026-09-01', data_fim: '2026-09-10' },
    { ...base, solicitacao_id: 's3', integracao_id: null, integracao_tipo: null, escopo: 'apurar_ponto', data_inicio: '2026-10-01', data_fim: '2026-10-05' },
    { ...base, solicitacao_id: 's4', integracao_id: null, integracao_tipo: null, escopo: 'exportar_fechamento', parametros: { fechamento_id: 'f1' } },
    { ...base, solicitacao_id: 's5', integracao_id: ACESSO_ID, integracao_tipo: 'controlid_acesso', escopo: 'vendas' },
  ]
  const r = await executarWorkflow(WF.fila, [], ctx)
  assert.equal(r.erro, null, r.erro && r.erro.message)
  const concl = Object.fromEntries(sb.chamadas.slice(n).filter((c) => c.rpc === 'ingestao_sync_concluir_solicitacao').map((c) => [c.args.p_solicitacao, c.args]))
  assert.deepEqual(Object.keys(concl).sort(), ['s1', 's2', 's3', 's4', 's5'])
  assert.equal(concl.s1.p_status, 'concluida', concl.s1.p_mensagem)
  assert.equal(concl.s2.p_status, 'concluida')
  assert.equal(concl.s2.p_execucao, 'x-batidas')
  assert.equal(concl.s3.p_status, 'concluida')
  assert.equal(concl.s4.p_status, 'concluida', concl.s4.p_mensagem)
  assert.equal(concl.s5.p_status, 'erro')
  assert.match(concl.s5.p_mensagem, /não se aplica/)
  // Control iD: usuários → exportar (envio ativo) → batidas, com as datas da solicitação
  assert.deepEqual(chamadasControlid.map((c) => c.wf), ['usuarios', 'exportar', 'batidas'])
  assert.equal(chamadasControlid[0].entrada.data_inicio, '2026-09-01')
  assert.equal(chamadasControlid[0].entrada.gatilho, 'manual')
  assert.equal(chamadasControlid[0].entrada.solicitacao_id, 's2')
  // apurar ponto direto, com execução própria
  const ap = sb.chamadas.slice(n).find((c) => c.rpc === 'ingestao_apurar_ponto').args
  assert.deepEqual(ap, { p_empresa: EMPRESA, p_inicio: '2026-10-01', p_fim: '2026-10-05' })
  // exportação: e-mail com CSV anexo
  assert.equal(ctx.emails.length, 1)
  assert.equal(ctx.emails[0].para, 'gerente@barbossanova.com.br')
  const anexo = ctx.emails[0].anexos.data
  assert.equal(anexo.fileName, 'comissao_bar-bossa-nova_2026-09-01_2026-09-30.csv')
  const csv = Buffer.from(anexo.data, 'base64').toString('utf8')
  assert.ok(csv.startsWith('﻿Período;01/09/2026 a 30/09/2026\r\n'))
  // zig com o dia pedido
  const iniZig = sb.chamadas.slice(n).find((c) => c.rpc === 'ingestao_sync_iniciar' && c.args.p_tipo === 'zig_importar').args
  assert.equal(iniZig.p_periodo_inicio, '2026-10-06')
})

test('Sincronizar agora: fila vazia não faz nada além de consultar', async () => {
  const n = sb.chamadas.length
  fila = []
  const r = await executarWorkflow(WF.fila, [], ctx)
  assert.equal(r.erro, null)
  assert.deepEqual(rpcsDesde(n), ['ingestao_sync_pegar_solicitacoes'])
})

test('Sincronizar agora: variável MDG_WF_* faltando → solicitação com erro e execução registrada', async () => {
  const n = sb.chamadas.length
  fila = [{ solicitacao_id: 's6', empresa_id: EMPRESA, integracao_id: ZIG_ID, integracao_tipo: 'zig', escopo: 'tudo', parametros: {} }]
  const r = await executarWorkflow(WF.fila, [], { ...ctx, env: { ...ctx.env, MDG_WF_ZIG_IMPORTAR: '' } })
  assert.equal(r.erro, null, r.erro && r.erro.message)
  const c = sb.chamadas.slice(n).find((x) => x.rpc === 'ingestao_sync_concluir_solicitacao').args
  assert.equal(c.p_status, 'erro')
  assert.match(c.p_mensagem, /MDG_WF_ZIG_IMPORTAR/)
  assert.ok(c.p_execucao)
  assert.equal(sb.chamadas.slice(n).find((x) => x.rpc === 'ingestao_sync_finalizar').args.p_status, 'erro')
})

test('Agendador: roda as integrações vencidas com gatilho agendado', async () => {
  chamadasControlid.length = 0
  vencidas = [
    { integracao_id: ZIG_ID, empresa_id: EMPRESA, tipo: 'zig', nome: 'Zig', intervalo_minutos: 60, ultima_execucao_em: null },
    { integracao_id: ACESSO_ID, empresa_id: EMPRESA, tipo: 'controlid_acesso', nome: 'iDFace', intervalo_minutos: 15, ultima_execucao_em: null },
  ]
  const n = sb.chamadas.length
  const r = await executarWorkflow(WF.agendador, [], ctx)
  assert.equal(r.erro, null, r.erro && r.erro.message)
  const resumo = r.saida[0].json
  assert.equal(resumo.total, 4)
  assert.equal(resumo.erros, 0)
  assert.deepEqual(sb.chamadas.slice(n).find((c) => c.rpc === 'ingestao_integracoes_ativas').args, { p_tipo: null, p_somente_vencidas: true })
  assert.equal(sb.chamadas.slice(n).find((c) => c.rpc === 'ingestao_sync_iniciar').args.p_gatilho, 'agendado')
  assert.deepEqual(chamadasControlid.map((c) => [c.wf, c.entrada.gatilho, c.entrada.escopo]), [['usuarios', 'agendado', 'tudo'], ['exportar', 'agendado', 'tudo'], ['batidas', 'agendado', 'tudo']])
  vencidas = []
})

test('Rotina diária: apura ponto e gera tarefas, cada um com sua execução', async () => {
  const n = sb.chamadas.length
  const r = await executarWorkflow(WF.rotina, [], ctx)
  assert.equal(r.erro, null, r.erro && r.erro.message)
  assert.deepEqual(rpcsDesde(n), ['ingestao_sync_iniciar', 'ingestao_apurar_ponto', 'ingestao_sync_finalizar', 'ingestao_sync_iniciar', 'ingestao_tarefas_gerar', 'ingestao_sync_finalizar'])
  const tipos = sb.chamadas.slice(n).filter((c) => c.rpc === 'ingestao_sync_iniciar').map((c) => c.args.p_tipo)
  assert.deepEqual(tipos, ['apurar_ponto', 'tarefas_gerar'])
  assert.equal(r.saida[0].json.tarefas_gerar.gravados, 2)
})

test('Exportar fechamento: falha de e-mail fecha execução com erro; fechamento inexistente quebra o subfluxo', async () => {
  const entrada = { empresa_id: EMPRESA, escopo: 'exportar_fechamento', gatilho: 'manual', solicitacao_id: 's7', parametros: { fechamento_id: 'f1' } }
  const r = await executarWorkflow(WF.exportar, [{ json: entrada }], { ...ctx, falharEmail: true })
  assert.equal(r.saida[0].json.status, 'erro')
  assert.match(r.saida[0].json.erro, /SMTP/)
  const n = sb.chamadas.length
  const r2 = await executarWorkflow(WF.exportar, [{ json: { ...entrada, parametros: { fechamento_id: 'nao-existe' } } }], ctx)
  assert.match(r2.erro.message, /Fechamento não encontrado/)
  assert.equal(sb.chamadas.slice(n).find((c) => c.rpc === 'ingestao_sync_finalizar').args.p_status, 'erro')
})

test('Tratador de erros: fecha as execuções presas da execução que falhou e avisa por e-mail', async () => {
  ctx.emails.length = 0
  const n = sb.chamadas.length
  const r = await executarWorkflow(WF.erros, [{ json: { execution: { id: '777', url: 'http://n8n/execution/777', lastNodeExecuted: 'Importar Zig', error: { message: 'boom' }, mode: 'trigger' }, workflow: { id: 'wf-zig', name: 'MDG · Zig · Importar' } } }], ctx)
  assert.equal(r.erro, null, r.erro && r.erro.message)
  const fin = sb.chamadas.slice(n).find((c) => c.rpc === 'ingestao_sync_finalizar').args
  assert.equal(fin.p_execucao, 'exec-aberta')
  assert.equal(fin.p_status, 'erro')
  assert.match(fin.p_erro, /MDG · Zig · Importar: boom \(nó "Importar Zig"\)/)
  assert.equal(ctx.emails.length, 1)
  assert.match(ctx.emails[0].assunto, /Erro no N8N/)
  // sem e-mail configurado: não envia
  ctx.emails.length = 0
  await executarWorkflow(WF.erros, [{ json: { execution: { id: '1', error: { message: 'x' } }, workflow: { name: 'W' } } }], { ...ctx, env: { ...ctx.env, MDG_EMAIL_RELATORIOS: '' } })
  assert.equal(ctx.emails.length, 0)
})
