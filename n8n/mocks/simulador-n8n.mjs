// Simulador MÍNIMO de execução de workflows N8N, só para testes: roda os nós usados pelos workflows MDG
// (gatilhos, Code, Switch v3, IF v2, Execute Workflow, Send Email, Sticky Note) com o código de verdade dos nós Code,
// injetando `this.helpers.httpRequest`, `$env`, `$vars`, `$execution`, `$input` e `$('Nó')`.
// NÃO é o N8N: serve para pegar erro de código/fiação antes de importar. A validação final é importar no N8N.

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor

/** `this.helpers.httpRequest` do N8N, implementado com fetch (subconjunto usado pelas libs). */
export function helpersFetch(registro) {
  return {
    async httpRequest(o) {
      registro?.push({ method: o.method, url: o.url })
      const controle = new AbortController()
      const t = setTimeout(() => controle.abort(), o.timeout || 60000)
      try {
        const r = await fetch(o.url, {
          method: o.method || 'GET',
          headers: o.headers,
          body: o.body === undefined ? undefined : typeof o.body === 'string' ? o.body : JSON.stringify(o.body),
          signal: controle.signal,
        })
        const texto = await r.text()
        let body = texto
        if (o.json && texto) { try { body = JSON.parse(texto) } catch { body = texto } }
        if (!o.ignoreHttpStatusErrors && r.status >= 400) throw Object.assign(new Error(`Request failed with status code ${r.status}`), { httpCode: r.status })
        const headers = {}
        r.headers.forEach((v, k) => { headers[k] = v })
        return o.returnFullResponse ? { body, headers, statusCode: r.status } : body
      } finally {
        clearTimeout(t)
      }
    },
    async prepareBinaryData(buffer, fileName, mimeType) {
      return { data: buffer.toString('base64'), fileName, mimeType, fileSize: String(buffer.length) }
    },
  }
}

function avaliar(expr, item, env) {
  if (typeof expr !== 'string' || !expr.startsWith('=')) return expr
  return expr.slice(1).replace(/\{\{([\s\S]+?)\}\}/g, (_, e) => {
    const v = new Function('$json', '$env', `return (${e})`)(item.json, env)
    return v === undefined || v === null ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v)
  })
}
function condicao(c, item, env) {
  const esq = avaliar(c.leftValue, item, env)
  const dir = avaliar(c.rightValue, item, env)
  switch (c.operator.operation) {
    case 'equals': return esq === dir
    case 'notEquals': return esq !== dir
    case 'notEmpty': return esq !== '' && esq !== undefined && esq !== null
    case 'empty': return esq === '' || esq === undefined || esq === null
    default: throw new Error(`operação não suportada no simulador: ${c.operator.operation}`)
  }
}
const conjunto = (cond, item, env) => (cond.combinator === 'or' ? cond.conditions.some((c) => condicao(c, item, env)) : cond.conditions.every((c) => condicao(c, item, env)))

/**
 * Executa um workflow. ctx = { env, vars, workflows: {id: wfJson}, emails: [], http: [], falharEmail?: bool, execucao: n }
 * Retorna { saida (itens do último nó executado), dados: {nó: {entrada, saidas}}, erro }.
 */
export async function executarWorkflow(wf, itens, ctx) {
  ctx.execucao = (ctx.execucao || 1000) + 1
  const execucaoId = String(ctx.execucao)
  const nos = Object.fromEntries(wf.nodes.map((n) => [n.name, n]))
  const dados = {}
  const gatilho = wf.nodes.find((n) => /Trigger$|scheduleTrigger$/.test(n.type))
  if (!gatilho) throw new Error('workflow sem gatilho')
  let ultimo = null
  const fila = [[gatilho.name, (itens && itens.length ? itens : [{ json: {} }]).map((i) => ({ json: i.json, binary: i.binary, __origem: {} }))]]

  while (fila.length) {
    const [nome, entrada] = fila.shift()
    const no = nos[nome]
    let saidas
    try {
      saidas = await executarNo(no, entrada, dados, ctx, execucaoId)
    } catch (e) {
      if (no.onError === 'continueRegularOutput') saidas = [entrada.map((it) => ({ json: { error: { message: e.message } }, __origem: it.__origem }))]
      else return { saida: null, dados, erro: Object.assign(e, { no: nome, execucaoId }) }
    }
    // rastreio de origem para itemMatching
    saidas = saidas.map((lista) => lista.map((it, i) => {
      const base = it.__origem || (entrada.length === lista.length ? entrada[i].__origem : entrada.length === 1 ? entrada[0].__origem : {})
      return { ...it, __origem: { ...base, [nome]: it.json } }
    }))
    dados[nome] = { entrada, saidas }
    ultimo = nome
    const cons = (wf.connections[nome] && wf.connections[nome].main) || []
    cons.forEach((alvos, idx) => {
      const lista = saidas[idx] || []
      if (!lista.length) return
      for (const a of alvos || []) fila.push([a.node, lista])
    })
  }
  const final = dados[ultimo].saidas[0] || []
  return { saida: final.map((i) => ({ json: i.json, binary: i.binary })), dados, erro: null, execucaoId }
}

async function executarNo(no, entrada, dados, ctx, execucaoId) {
  const env = ctx.env || {}
  const t = no.type
  if (/Trigger$|scheduleTrigger$/.test(t)) return [entrada]
  if (t === 'n8n-nodes-base.code') {
    const $ = (nome) => {
      const d = dados[nome]
      if (!d) throw new Error(`nó "${nome}" ainda não executou`)
      return {
        all: (branch = 0) => (d.saidas[branch] || []).map((i) => ({ json: i.json, binary: i.binary })),
        first: () => ({ json: d.saidas[0][0].json }),
        itemMatching: (i) => {
          const j = entrada[i] && entrada[i].__origem[nome]
          if (!j) throw new Error(`sem item ligado a "${nome}"`)
          return { json: j }
        },
      }
    }
    const $input = { all: () => entrada.map((i) => ({ json: i.json, binary: i.binary })), first: () => ({ json: entrada[0].json, binary: entrada[0].binary }) }
    const ctxThis = { helpers: helpersFetch(ctx.http) }
    const fn = new AsyncFunction('$input', '$', '$env', '$vars', '$execution', 'Buffer', no.parameters.jsCode)
    const r = await fn.call(ctxThis, $input, $, env, ctx.vars || {}, { id: execucaoId }, Buffer)
    if (!Array.isArray(r)) throw new Error('Code deve devolver uma lista de itens')
    return [r.map((x) => ({ json: x.json, binary: x.binary }))]
  }
  if (t === 'n8n-nodes-base.switch') {
    const regras = no.parameters.rules.values
    const fb = no.parameters.options && no.parameters.options.fallbackOutput
    const saidas = regras.map(() => [])
    for (const it of entrada) {
      const k = regras.findIndex((r) => conjunto(r.conditions, it, env))
      if (k >= 0) saidas[k].push(it)
      else if (typeof fb === 'number') saidas[fb].push(it)
    }
    return saidas
  }
  if (t === 'n8n-nodes-base.if') {
    const s = [[], []]
    for (const it of entrada) s[conjunto(no.parameters.conditions, it, env) ? 0 : 1].push(it)
    return s
  }
  if (t === 'n8n-nodes-base.executeWorkflow') {
    const out = []
    for (const it of entrada) {
      const id = avaliar(no.parameters.workflowId, it, env)
      const sub = ctx.workflows[id]
      if (!sub) throw new Error(`Workflow ${id} não encontrado`)
      const r = await executarWorkflow(sub, [{ json: it.json }], ctx)
      if (r.erro) {
        if (no.onError === 'continueRegularOutput') { out.push({ json: { error: { message: r.erro.message } }, __origem: it.__origem }); continue }
        throw r.erro
      }
      for (const s of r.saida) out.push({ json: s.json, __origem: it.__origem })
    }
    return [out]
  }
  if (t === 'n8n-nodes-base.emailSend') {
    const out = []
    for (const it of entrada) {
      if (ctx.falharEmail) throw new Error('SMTP indisponível')
      const p = no.parameters
      ctx.emails = ctx.emails || []
      ctx.emails.push({ de: avaliar(p.fromEmail, it, env), para: avaliar(p.toEmail, it, env), assunto: avaliar(p.subject, it, env), texto: avaliar(p.text, it, env), anexos: it.binary || null })
      out.push({ json: { success: true } })
    }
    return [out]
  }
  if (t === 'n8n-nodes-base.stickyNote') return [[]]
  throw new Error(`tipo de nó não suportado no simulador: ${t}`)
}
