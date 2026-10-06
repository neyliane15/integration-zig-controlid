// Valida os workflows do Control iD e os EXECUTA de ponta a ponta com um mini-executor que imita o N8N
// (Execute Workflow Trigger, HTTP Request, Code, IF; ordem v1): o código que roda é o `jsCode` gravado no JSON,
// falando com o mock do n2 (equipamentos) e com um Supabase falso em memória (RPCs de ingestão).
// Rodam com `node --test n8n/controlid/` e com `npm test` (vitest).
import assert from 'node:assert/strict'
import { readFileSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { WORKFLOWS, libSemExport } from './montar-workflows.mjs'

const { describe, it, before, after } = process.env.VITEST
  ? await import('vitest').then((v) => ({ ...v, before: v.beforeAll, after: v.afterAll }))
  : await import('node:test')

const PASTA = dirname(fileURLToPath(import.meta.url))
const CAMINHO_MOCK = join(PASTA, '..', 'mocks', 'servidor.mjs')
const ler = (arquivo) => JSON.parse(readFileSync(join(PASTA, 'workflows', arquivo), 'utf8'))
const NOMES = {
  'controlid-importar-usuarios.json': 'MDG · Control iD · Importar usuários',
  'controlid-importar-batidas.json': 'MDG · Control iD · Importar batidas',
  'controlid-exportar-usuarios.json': 'MDG · Control iD · Exportar funcionários',
}

describe('workflows: estrutura', () => {
  for (const arquivo of Object.keys(WORKFLOWS)) {
    it(arquivo, () => {
      const wf = ler(arquivo)
      assert.equal(wf.name, NOMES[arquivo])
      assert.equal(wf.settings.executionOrder, 'v1')
      const nomes = new Set(wf.nodes.map((n) => n.name))
      assert.equal(nomes.size, wf.nodes.length, 'nomes de nó repetidos')
      assert.equal(new Set(wf.nodes.map((n) => n.id)).size, wf.nodes.length, 'ids repetidos')
      const gatilhos = wf.nodes.filter((n) => n.type === 'n8n-nodes-base.executeWorkflowTrigger')
      assert.equal(gatilhos.length, 1)
      // conexões apontam para nós existentes; todo nó é alcançável a partir do gatilho
      const alcancados = new Set([gatilhos[0].name])
      const fila = [gatilhos[0].name]
      for (const [de, c] of Object.entries(wf.connections)) {
        assert.ok(nomes.has(de), `origem inexistente: ${de}`)
        for (const saida of c.main) for (const l of saida) assert.ok(nomes.has(l.node), `destino inexistente: ${l.node}`)
      }
      while (fila.length) {
        const n = fila.shift()
        for (const saida of wf.connections[n]?.main || []) for (const l of saida) if (!alcancados.has(l.node)) { alcancados.add(l.node); fila.push(l.node) }
      }
      assert.deepEqual([...nomes].filter((n) => !alcancados.has(n)), [])
      // o JSON está igual ao que o gerador produz (cópias // @lib em dia)
      assert.deepEqual(wf, JSON.parse(JSON.stringify(WORKFLOWS[arquivo]())), 'rode: node n8n/controlid/montar-workflows.mjs')
      for (const n of wf.nodes.filter((x) => x.type === 'n8n-nodes-base.code')) {
        const m = /^\/\/ @lib (\S+)\n/.exec(n.parameters.jsCode)
        if (m) assert.ok(n.parameters.jsCode.startsWith(`// @lib ${m[1]}\n${libSemExport(m[1])}`), `cópia da lib desatualizada em ${n.name}`)
        assert.doesNotMatch(n.parameters.jsCode.replace(/^\/\/ @lib .*\n/, ''), /^export /m)
        new Function(`return (async function () { ${n.parameters.jsCode} })`) // sintaxe válida
      }
      for (const n of wf.nodes.filter((x) => x.type === 'n8n-nodes-base.httpRequest')) {
        assert.equal(n.retryOnFail, true)
        assert.equal(n.maxTries, 3)
        assert.match(n.parameters.url, /^=\{\{ \$env\.SUPABASE_URL \}\}\/rest\/v1\/rpc\/ingestao_/)
      }
      // nada de credencial no JSON
      const texto = JSON.stringify(wf)
      assert.doesNotMatch(texto, /eyJ[A-Za-z0-9_-]{10,}/)
      assert.doesNotMatch(texto, /"(password|senha)"\s*:\s*"[^"]+"/)
      assert.doesNotMatch(texto, /192\.168\.|127\.0\.0\.1/)
    })
  }
})

// ------------------------------------------------------------------------------------- mini-executor N8N

function avaliar(expr, ctx) {
  const f = new Function('$json', '$', '$execution', '$env', '$workflow', `return (${expr});`)
  return f(ctx.$json, ctx.$, ctx.$execution, ctx.$env, ctx.$workflow)
}
function parametro(valor, ctx) {
  if (typeof valor !== 'string' || !valor.startsWith('=')) return valor
  const t = valor.slice(1)
  const unico = /^\{\{([\s\S]*)\}\}$/.exec(t)
  if (unico && !unico[1].includes('}}')) return avaliar(unico[1], ctx)
  return t.replace(/\{\{([\s\S]*?)\}\}/g, (_, e) => String(avaliar(e, ctx)))
}

async function httpRequestN8n(op) {
  const binario = op.body instanceof Uint8Array
  const r = await fetch(op.url, {
    method: op.method || 'GET', headers: op.headers, body: op.body,
    signal: AbortSignal.timeout(op.timeout || 30000), ...(binario ? { duplex: 'half' } : {}),
  })
  const bruto = new Uint8Array(await r.arrayBuffer())
  let body = op.encoding === 'arraybuffer' ? bruto : new TextDecoder().decode(bruto)
  if (!op.ignoreHttpStatusErrors && r.status >= 400) throw new Error('HTTP ' + r.status)
  return op.returnFullResponse ? { statusCode: r.status, body } : body
}

async function executar(wf, entrada, { supabase, env }) {
  const nos = Object.fromEntries(wf.nodes.map((n) => [n.name, n]))
  const saidas = {}
  const execucao = { id: String(Math.floor(Math.random() * 1e6)) }
  const $ = (nome) => {
    if (!saidas[nome]) throw new Error(`Node '${nome}' hasn't been executed`)
    return { first: () => saidas[nome][0], all: () => saidas[nome] }
  }
  const ctxDe = (item) => ({ $json: item?.json ?? {}, $, $execution: execucao, $env: env, $workflow: { name: wf.name } })
  const gatilho = wf.nodes.find((n) => n.type === 'n8n-nodes-base.executeWorkflowTrigger')
  const fila = [[gatilho.name, [{ json: entrada }]]]
  let ultimo = null
  while (fila.length) {
    const [nome, itens] = fila.shift()
    const no = nos[nome]
    let porSaida
    if (no.type === 'n8n-nodes-base.executeWorkflowTrigger') porSaida = [itens]
    else if (no.type === 'n8n-nodes-base.code') {
      const ctx = { helpers: { httpRequest: httpRequestN8n } }
      const f = new Function('$', '$input', '$env', '$execution', `return (async function () { ${no.parameters.jsCode} }).call(this)`)
      const r = await f.call(ctx, $, { all: () => itens, first: () => itens[0] }, env, execucao)
      porSaida = [r]
    } else if (no.type === 'n8n-nodes-base.if') {
      const c = no.parameters.conditions.conditions[0]
      const v = [[], []]
      for (const it of itens) v[parametro(c.leftValue, ctxDe(it)) ? 0 : 1].push(it)
      porSaida = v
    } else if (no.type === 'n8n-nodes-base.httpRequest') {
      const out = []
      for (const it of itens) {
        const url = parametro(no.parameters.url, ctxDe(it))
        const rpc = url.split('/rest/v1/rpc/')[1]
        const corpo = JSON.parse(parametro(no.parameters.jsonBody, ctxDe(it)))
        try {
          const r = await supabase(rpc, corpo)
          if (Array.isArray(r)) out.push(...r.map((json) => ({ json })))
          else if (r === null || r === undefined) out.push({ json: {} })
          else if (typeof r !== 'object') out.push({ json: { data: r } })
          else out.push({ json: r })
        } catch (e) {
          if (no.onError === 'continueRegularOutput') out.push({ json: { error: { message: e.message } } })
          else throw e
        }
      }
      if (!out.length && no.alwaysOutputData) out.push({ json: {} })
      porSaida = [out]
    } else throw new Error('tipo não suportado: ' + no.type)
    saidas[nome] = porSaida.flat()
    ultimo = nome
    const conexoes = wf.connections[nome]?.main || []
    conexoes.forEach((destinos, i) => {
      const its = porSaida[i] || []
      if (!its.length) return
      for (const d of destinos) fila.push([d.node, its])
    })
  }
  return { saida: saidas[ultimo], ultimo, saidas }
}

/** Supabase falso: RPCs de ingestão em memória, com a idempotência do contrato (on conflict do nothing). */
function supabaseFalso(configs) {
  const estado = { execucoes: {}, batidas: new Map(), usuarios: new Map(), chamadas: [], envios: [], pendencias: null }
  let seq = 0
  const fn = async (rpc, c) => {
    estado.chamadas.push({ rpc, corpo: c })
    switch (rpc) {
      case 'ingestao_sync_iniciar': {
        const id = `e0000000-0000-4000-8000-${String(++seq).padStart(12, '0')}`
        estado.execucoes[id] = { ...c, status: 'executando' }
        return id
      }
      case 'ingestao_integracao_config': {
        if (!configs[c.p_integracao]) throw new Error('Integração não encontrada')
        return configs[c.p_integracao]
      }
      case 'ingestao_controlid_usuarios':
        estado.usuarios.set(c.p_integracao, c.p_usuarios)
        return { lidos: c.p_usuarios.length, gravados: c.p_usuarios.length, ignorados: 0, inseridos: 0, atualizados: c.p_usuarios.length, removidos: 0, vinculados_automaticamente: 0, sem_vinculo: 0 }
      case 'ingestao_controlid_batidas': {
        assert.ok(c.p_batidas.length <= 2000)
        let gravados = 0
        let duplicados = 0
        for (const b of c.p_batidas) {
          assert.ok(('instante' in b) !== ('instante_local' in b), 'exatamente um de instante/instante_local')
          const k = c.p_integracao + '|' + b.id_externo
          if (estado.batidas.has(k)) duplicados++
          else { estado.batidas.set(k, b); gravados++ }
        }
        return { lidos: c.p_batidas.length, gravados, ignorados: 0, duplicados, sem_funcionario: 0, dias_apurados: 1, cursor: {} }
      }
      case 'ingestao_controlid_envios_pendentes':
        return estado.pendencias || { itens: [] }
      case 'ingestao_controlid_envio_resultado':
        estado.envios.push(c)
        return { status: c.p_status, versao: c.p_versao }
      case 'ingestao_sync_finalizar':
        Object.assign(estado.execucoes[c.p_execucao], { status: c.p_status, final: c })
        return null
      default:
        throw new Error('RPC desconhecida: ' + rpc)
    }
  }
  return { fn, estado }
}

describe('workflows: execução ponta a ponta (mini-executor + mock do n2)', { skip: !existsSync(CAMINHO_MOCK) && 'mock ausente' }, () => {
  let mocks, dia
  const ACESSO = 'a0000000-0000-4000-8000-000000000102'
  const REP = 'a0000000-0000-4000-8000-000000000103'
  const env = { SUPABASE_URL: 'http://supabase.falso', SUPABASE_SERVICE_ROLE_KEY: 'chave' }
  const entrada = (integracao, extra = {}) => ({ integracao_id: integracao, empresa_id: 'a0000000-0000-4000-8000-00000000000a', tipo: null, escopo: 'tudo', gatilho: 'manual', solicitacao_id: null, data_inicio: null, data_fim: null, parametros: {}, ...extra })
  const configs = () => ({
    [ACESSO]: { integracao_id: ACESSO, tipo: 'controlid_acesso', nome: 'iDFace', ativa: true, parametros: { dias_retroativos: 7, relogio_em_hora_local: true, espera_segundos: 0 }, segredos: { url: `127.0.0.1:${mocks.portas.acesso}`, login: 'admin', senha: 'admin' }, cursor: {}, fuso: 'America/Sao_Paulo', virada_dia: '05:00:00', dia_trabalho_atual: dia },
    [REP]: { integracao_id: REP, tipo: 'controlid_rep', nome: 'iDClass', ativa: true, parametros: { dias_retroativos: 7, identificador: 'cpf', espera_segundos: 0 }, segredos: { url: `http://127.0.0.1:${mocks.portas.rep}`, login: 'admin', senha: 'admin' }, cursor: {}, fuso: 'America/Sao_Paulo', virada_dia: '05:00:00', dia_trabalho_atual: dia },
  })

  before(async () => {
    const { iniciarMocks } = await import(CAMINHO_MOCK)
    mocks = await iniciarMocks({ zig: 0, acesso: 0, rep: 0 })
    dia = (await (await fetch(`http://127.0.0.1:${mocks.portas.acesso}/__mock/estado`)).json()).dia_trabalho
  })
  after(async () => { if (mocks) await mocks.fechar() })

  it('Importar usuários (acesso e REP)', async () => {
    for (const [id, n] of [[ACESSO, 5], [REP, 5]]) {
      const sb = supabaseFalso(configs())
      const r = await executar(ler('controlid-importar-usuarios.json'), entrada(id), { supabase: sb.fn, env })
      assert.equal(r.ultimo, 'Saída')
      assert.equal(r.saida[0].json.status, 'sucesso', r.saida[0].json.erro)
      assert.equal(r.saida[0].json.gravados, n)
      assert.equal(sb.estado.usuarios.get(id).length, n)
      const exec = Object.values(sb.estado.execucoes)[0]
      assert.equal(exec.p_tipo, 'controlid_usuarios')
      assert.equal(exec.p_workflow, 'MDG · Control iD · Importar usuários')
      assert.equal(exec.status, 'sucesso')
    }
  })

  it('Importar usuários: senha errada → erro registrado, nada gravado', async () => {
    const cfg = configs()
    cfg[ACESSO].segredos.senha = 'x'
    const sb = supabaseFalso(cfg)
    const r = await executar(ler('controlid-importar-usuarios.json'), entrada(ACESSO), { supabase: sb.fn, env })
    assert.equal(r.saida[0].json.status, 'erro')
    assert.match(r.saida[0].json.erro, /Login recusado/)
    assert.equal(sb.estado.usuarios.size, 0)
    assert.equal(Object.values(sb.estado.execucoes)[0].status, 'erro')
  })

  it('Importar usuários: integração inexistente → erro na sync_execucoes', async () => {
    const sb = supabaseFalso({})
    const r = await executar(ler('controlid-importar-usuarios.json'), entrada('00000000-0000-4000-8000-000000000000'), { supabase: sb.fn, env })
    assert.equal(r.saida[0].json.status, 'erro')
    assert.match(r.saida[0].json.erro, /Integração não encontrada/)
  })

  it('Importar batidas (acesso e REP), idempotente na segunda execução', async () => {
    for (const id of [ACESSO, REP]) {
      const sb = supabaseFalso(configs())
      const wf = ler('controlid-importar-batidas.json')
      const r1 = await executar(wf, entrada(id), { supabase: sb.fn, env })
      assert.equal(r1.saida[0].json.status, 'sucesso', r1.saida[0].json.erro)
      assert.ok(r1.saida[0].json.gravados > 20)
      const r2 = await executar(wf, entrada(id), { supabase: sb.fn, env })
      assert.equal(r2.saida[0].json.status, 'sucesso')
      assert.equal(r2.saida[0].json.gravados, 0)
      assert.equal(r2.saida[0].json.ignorados, r1.saida[0].json.gravados)
      const execs = Object.values(sb.estado.execucoes)
      assert.ok(execs.every((e) => e.p_tipo === 'controlid_batidas' && e.status === 'sucesso'))
      if (id === REP) assert.equal(execs[0].final.p_detalhes.afd.ignoradas, 0)
    }
  })

  it('Importar batidas: equipamento fora do ar → erro, sem gravar', async () => {
    const cfg = configs()
    cfg[REP].segredos.url = 'http://127.0.0.1:9' // porta "discard": fetch recusa
    cfg[REP].parametros.tentativas = 1
    const sb = supabaseFalso(cfg)
    const r = await executar(ler('controlid-importar-batidas.json'), entrada(REP), { supabase: sb.fn, env })
    assert.equal(r.saida[0].json.status, 'erro')
    assert.equal(sb.estado.chamadas.some((c) => c.rpc === 'ingestao_controlid_batidas'), false)
  })

  it('Exportar funcionários (envio): registra resultado por item', async () => {
    await fetch(`http://127.0.0.1:${mocks.portas.acesso}/__mock/reset`, { method: 'POST' })
    const sb = supabaseFalso(configs())
    sb.estado.pendencias = {
      integracao_id: ACESSO, tipo: 'controlid_acesso', modelo: 'iDFace', identificador: 'cpf',
      envio: { ativo: true, foto: false, cartao: true, senha: true, horarios: true, ao_desligar: 'remover' },
      itens: [
        { envio_id: 'e1', versao: 1, alvo: 'funcionario', operacao: 'salvar', funcionario_id: 'f', id_remoto: null, usuario: { nome: 'Novo', matricula: '9' }, senha: '1234', cartoes: ['42'], foto: null, regras_acesso: [] },
        { envio_id: 'e2', versao: 3, alvo: 'funcionario', operacao: 'salvar', funcionario_id: 'g', id_remoto: '2', usuario: { nome: 'Bruno #ERRO', matricula: '2' }, senha: null, cartoes: [], foto: null, regras_acesso: [] },
      ],
    }
    const r = await executar(ler('controlid-exportar-usuarios.json'), entrada(ACESSO, { escopo: 'exportar_funcionarios' }), { supabase: sb.fn, env })
    assert.equal(r.saida[0].json.status, 'parcial')
    assert.deepEqual(sb.estado.envios.map((e) => [e.p_envio, e.p_status]), [['e1', 'enviado'], ['e2', 'erro']])
    assert.match(sb.estado.envios[0].p_id_remoto, /^\d+$/)
    assert.match(sb.estado.envios[1].p_erro, /#ERRO/)
    assert.equal(Object.values(sb.estado.execucoes)[0].p_tipo, 'controlid_exportar_usuarios')
    // sem pendências: sucesso sem tocar no equipamento
    const sb2 = supabaseFalso(configs())
    const r2 = await executar(ler('controlid-exportar-usuarios.json'), entrada(ACESSO), { supabase: sb2.fn, env })
    assert.equal(r2.saida[0].json.status, 'sucesso')
    assert.equal(sb2.estado.envios.length, 0)
  })
})
