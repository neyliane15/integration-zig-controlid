// Integração REAL N8N ↔ banco (revisão 1): executa os JSON de verdade dos workflows (fila "Sincronizar agora" → subfluxos
// Zig e Control iD, rotina diária e exportação do fechamento) no simulador (`mocks/simulador-n8n.mjs`, agora com nó HTTP
// Request), contra os mocks da Zig/Control iD e o Supabase LOCAL de verdade (PostgREST + migrações + carga demo).
// Pega qualquer divergência entre o que o N8N manda e as assinaturas reais das RPCs (nomes de parâmetros, formatos, retorno).
//
// Opt-in, porque grava no banco local:  npm run local  &&  MDG_INTEGRACAO_REAL=1 node --test n8n/integracao-real.test.mjs
// (URL do .env.local; service_role de `node ferramentas/local/portao.mjs --chaves`, ou MDG_SUPABASE_URL / MDG_SERVICE_ROLE_KEY).
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { executarWorkflow } from './mocks/simulador-n8n.mjs'
import { iniciarMocks } from './mocks/servidor.mjs'

const { describe, it, before, after } = process.env.VITEST
  ? await import('vitest').then((v) => ({ ...v, before: v.beforeAll, after: v.afterAll }))
  : await import('node:test')

const N8N = dirname(fileURLToPath(import.meta.url))
const RAIZ = join(N8N, '..')
const ler = (rel) => JSON.parse(readFileSync(join(N8N, rel), 'utf8'))
const ATIVO = process.env.MDG_INTEGRACAO_REAL === '1'

const EMPRESA = 'a0000000-0000-4000-8000-00000000000a'
const ZIG = 'a0000000-0000-4000-8000-000000000101'
const ACESSO = 'a0000000-0000-4000-8000-000000000102'
const REP = 'a0000000-0000-4000-8000-000000000103'

function configLocal() {
  let url = process.env.MDG_SUPABASE_URL
  if (!url && existsSync(join(RAIZ, '.env.local'))) {
    url = /^VITE_SUPABASE_URL=(.+)$/m.exec(readFileSync(join(RAIZ, '.env.local'), 'utf8'))?.[1]?.trim()
  }
  let chave = process.env.MDG_SERVICE_ROLE_KEY
  if (!chave) chave = JSON.parse(execFileSync('node', [join(RAIZ, 'ferramentas/local/portao.mjs'), '--chaves'], { encoding: 'utf8' })).service_role
  return { url: url.replace(/\/+$/, ''), chave }
}

describe('integração real N8N × Supabase local', { skip: !ATIVO && 'defina MDG_INTEGRACAO_REAL=1 com `npm run local` no ar' }, () => {
  let sb, mocks, ctx, inicio
  const cab = () => ({ apikey: sb.chave, Authorization: `Bearer ${sb.chave}`, 'Content-Type': 'application/json' })
  const rpc = async (nome, args = {}) => {
    const r = await fetch(`${sb.url}/rest/v1/rpc/${nome}`, { method: 'POST', headers: cab(), body: JSON.stringify(args) })
    const t = await r.text()
    if (r.status >= 400) throw new Error(`${nome}: HTTP ${r.status} ${t}`)
    return t ? JSON.parse(t) : null
  }
  const tabela = async (caminho, opcoes = {}) => {
    const r = await fetch(`${sb.url}/rest/v1/${caminho}`, { headers: { ...cab(), Prefer: 'return=representation' }, ...opcoes })
    const t = await r.text()
    if (r.status >= 400) throw new Error(`${caminho}: HTTP ${r.status} ${t}`)
    return t ? JSON.parse(t) : null
  }
  const execucoesDesde = (filtro = '') =>
    tabela(`sync_execucoes?select=tipo,status,erro,integracao_id,registros_lidos,registros_gravados,registros_ignorados,detalhes&iniciado_em=gte.${encodeURIComponent(inicio)}${filtro}&order=iniciado_em`)
  const rodarFila = async () => {
    const r = await executarWorkflow(ctx.workflows.fila, [], ctx)
    assert.equal(r.erro, null, r.erro && `${r.erro.no}: ${r.erro.message}`)
    return r
  }

  before(async () => {
    sb = configLocal()
    mocks = await iniciarMocks({ zig: 0, acesso: 0, rep: 0 })
    const base = (q) => `http://127.0.0.1:${mocks.portas[q]}`
    // segredos das integrações demo apontando para os mocks desta execução
    for (const [id, q] of [[ACESSO, 'acesso'], [REP, 'rep']]) {
      await tabela(`integracoes_segredos?integracao_id=eq.${id}`, {
        method: 'PATCH', body: JSON.stringify({ segredos: { url: base(q), login: 'admin', senha: 'admin' } }),
      })
    }
    await tabela(`integracoes_segredos?integracao_id=eq.${ZIG}`, { method: 'PATCH', body: JSON.stringify({ segredos: { token: 'token-mock' } }) })
    // limpa pedidos antigos da fila desta empresa (execuções anteriores do teste)
    await tabela(`sync_solicitacoes?empresa_id=eq.${EMPRESA}&status=in.(pendente,em_andamento)`, {
      method: 'PATCH', body: JSON.stringify({ status: 'cancelada', mensagem: 'limpeza do teste de integração' }),
    })
    inicio = new Date().toISOString()
    ctx = {
      env: {
        SUPABASE_URL: sb.url, SUPABASE_SERVICE_ROLE_KEY: sb.chave, ZIG_BASE_URL: `${base('zig')}/integration`,
        MDG_WF_ZIG_IMPORTAR: 'wf-zig', MDG_WF_EXPORTAR_FECHAMENTO: 'wf-exp', MDG_WF_CONTROLID_USUARIOS: 'wf-u',
        MDG_WF_CONTROLID_BATIDAS: 'wf-b', MDG_WF_CONTROLID_EXPORTAR: 'wf-e', MDG_EMAIL_RELATORIOS: 'gerente@barbossanova.com.br',
      },
      workflows: {
        fila: ler('comum/workflows/sincronizar-agora.json'),
        'wf-zig': ler('zig/workflows/zig-importar.json'),
        'wf-exp': ler('comum/workflows/exportar-fechamento.json'),
        'wf-u': ler('controlid/workflows/controlid-importar-usuarios.json'),
        'wf-b': ler('controlid/workflows/controlid-importar-batidas.json'),
        'wf-e': ler('controlid/workflows/controlid-exportar-usuarios.json'),
      },
      emails: [], http: [], esperaRetentativaMs: 10,
    }
  })
  after(async () => { if (mocks) await mocks.fechar() })

  it('"Sincronizar agora" escopo tudo: Zig + Control iD acesso (usuários → envio → batidas) + REP, gravando no banco', async () => {
    const hoje = await rpc('dia_de_trabalho_atual', { p_empresa: EMPRESA })
    const ontem = new Date(Date.parse(hoje + 'T00:00:00Z') - 86400000).toISOString().slice(0, 10)
    const criadas = await rpc('sync_solicitar', { p_escopo: 'tudo', p_empresa: EMPRESA, p_data_inicio: ontem, p_data_fim: hoje })
    assert.equal(criadas, 3, 'uma solicitação por integração ativa (Zig, acesso, REP)')
    await rodarFila()

    const sol = await tabela(`sync_solicitacoes?select=status,mensagem,integracao_id&empresa_id=eq.${EMPRESA}&solicitado_em=gte.${encodeURIComponent(inicio)}`)
    assert.equal(sol.length, 3)
    for (const s of sol) assert.equal(s.status, 'concluida', `${s.integracao_id}: ${s.mensagem}`)

    const ex = await execucoesDesde()
    const porTipo = (t) => ex.filter((e) => e.tipo === t)
    for (const e of ex) assert.equal(e.status, 'sucesso', `${e.tipo}: ${e.erro}`)
    assert.equal(porTipo('zig_importar').length, 1)
    assert.equal(porTipo('controlid_usuarios').length, 2)
    assert.equal(porTipo('controlid_batidas').length, 2)
    assert.equal(porTipo('controlid_exportar_usuarios').length, 1, 'envio só no acesso (REP com envio desligado na carga demo)')
    assert.ok(porTipo('zig_importar')[0].registros_gravados > 0)

    // dados no banco
    const vendas = await rpc('vendas_resumo', { p_inicio: ontem, p_fim: hoje, p_empresa: EMPRESA })
    assert.ok(vendas[0].vendas > 0 && vendas[0].servico > 0 && vendas[0].faturamento > 0, JSON.stringify(vendas))
    const bandeiras = await tabela(`zig_faturamento_bandeiras?select=card_brand,valor&empresa_id=eq.${EMPRESA}&data_operacao=eq.${ontem}`)
    assert.ok(bandeiras.length > 0 && bandeiras.every((b) => b.card_brand && b.valor > 0))
    const usuarios = await tabela(`controlid_usuarios?select=user_id_externo,funcionario_id,vinculo&integracao_id=eq.${ACESSO}&removido_no_equipamento=eq.false`)
    assert.ok(usuarios.filter((u) => u.funcionario_id).length >= 5, 'os 5 usuários do mock ligados aos funcionários pela matrícula')
    const batAcesso = await tabela(`ponto_batidas?select=id,funcionario_id&integracao_id=eq.${ACESSO}`)
    const batRep = await tabela(`ponto_batidas?select=id,funcionario_id&integracao_id=eq.${REP}`)
    assert.ok(batAcesso.length > 0 && batAcesso.every((b) => b.funcionario_id), 'batidas do acesso com funcionário')
    assert.ok(batRep.length > 0 && batRep.every((b) => b.funcionario_id), 'batidas do REP (AFD) com funcionário pelo CPF')
    const envios = await tabela(`controlid_envios?select=status,erro,alvo&integracao_id=eq.${ACESSO}`)
    assert.ok(envios.some((e) => e.status === 'enviado'), JSON.stringify(envios))
    assert.ok(envios.every((e) => e.status !== 'erro'), JSON.stringify(envios.filter((e) => e.status === 'erro')))
  })

  it('reimportar batidas é idempotente (nada novo gravado) e a apuração/exportação passam pelo banco real', async () => {
    const antes = (await tabela(`ponto_batidas?select=id&integracao_id=in.(${ACESSO},${REP})`)).length
    inicio = new Date().toISOString()
    assert.equal(await rpc('sync_solicitar', { p_escopo: 'batidas', p_empresa: EMPRESA }), 2)
    const fech = await tabela(`comissao_fechamentos?select=id&empresa_id=eq.${EMPRESA}&status=eq.fechado&limit=1`)
    assert.equal(fech.length, 1, 'a carga demo tem um fechamento fechado')
    assert.equal(await rpc('sync_solicitar', { p_escopo: 'exportar_fechamento', p_empresa: EMPRESA, p_parametros: { fechamento_id: fech[0].id } }), 1)
    assert.equal(await rpc('sync_solicitar', { p_escopo: 'apurar_ponto', p_empresa: EMPRESA }), 1)
    await rodarFila()
    const depois = (await tabela(`ponto_batidas?select=id&integracao_id=in.(${ACESSO},${REP})`)).length
    assert.equal(depois, antes, 'nenhuma batida duplicada')
    const ex = await execucoesDesde()
    for (const e of ex) assert.equal(e.status, 'sucesso', `${e.tipo}: ${e.erro}`)
    assert.deepEqual(ex.filter((e) => e.tipo === 'controlid_batidas').map((e) => e.registros_gravados), [0, 0])
    assert.ok(ex.some((e) => e.tipo === 'apurar_ponto'))
    assert.ok(ex.some((e) => e.tipo === 'exportar_fechamento'))
    const email = ctx.emails.at(-1)
    assert.ok(email, 'e-mail do fechamento enviado')
    const anexo = Object.values(email.anexos || {})[0]
    const csv = Buffer.from(anexo.data, 'base64').toString('utf8')
    assert.ok(csv.startsWith('﻿') && csv.includes('Funcionário;Cargo;Incluído;Pontos;Dias trabalhados;Pontos efetivos;Valor (R$)'))
  })

  it('rotina diária e agendador contra o banco real', async () => {
    inicio = new Date().toISOString()
    const r = await executarWorkflow(ler('comum/workflows/rotina-diaria.json'), [], ctx)
    assert.equal(r.erro, null, r.erro && `${r.erro.no}: ${r.erro.message}`)
    const ex = await execucoesDesde()
    assert.deepEqual(ex.map((e) => [e.tipo, e.status]).sort(), [['apurar_ponto', 'sucesso'], ['tarefas_gerar', 'sucesso']])
    const ag = await executarWorkflow(ler('comum/workflows/agendador.json'), [], ctx)
    assert.equal(ag.erro, null, ag.erro && `${ag.erro.no}: ${ag.erro.message}`)
  })
})
