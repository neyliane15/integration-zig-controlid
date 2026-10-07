// Simulador MÍNIMO de execução de workflows N8N, só para testes: roda os nós usados pelos workflows MDG
// (gatilhos, Code, Switch v3, IF v2, Execute Workflow, HTTP Request v4, Send Email, Sticky Note) com o código de verdade dos nós Code,
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

/** Contexto das expressões `{{ }}`: $json, $env e (quando houver) $('Nó'), $execution. */
function exprCtx(item, env, extra) {
  return { $json: item.json, $env: env, $: extra?.$ || (() => { throw new Error('$() indisponível aqui') }), $execution: extra?.$execution || { id: '0' } }
}
function rodarExpr(e, c) {
  return new Function('$json', '$env', '$', '$execution', `return (${e})`)(c.$json, c.$env, c.$, c.$execution)
}
/** Avalia um parâmetro: `={{ x }}` sozinho devolve o valor cru (objeto, número…); com texto em volta vira texto. */
function avaliarParametro(expr, c) {
  if (typeof expr !== 'string' || !expr.startsWith('=')) return expr
  const t = expr.slice(1)
  const unico = /^\{\{([\s\S]*)\}\}$/.exec(t)
  if (unico && !unico[1].includes('}}')) return rodarExpr(unico[1], c)
  return t.replace(/\{\{([\s\S]+?)\}\}/g, (_, e) => {
    const v = rodarExpr(e, c)
    return v === undefined || v === null ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v)
  })
}
function avaliar(expr, item, env, extra) {
  if (typeof expr !== 'string' || !expr.startsWith('=')) return expr
  return expr.slice(1).replace(/\{\{([\s\S]+?)\}\}/g, (_, e) => {
    const v = rodarExpr(e, exprCtx(item, env, extra))
    return v === undefined || v === null ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v)
  })
}
function condicao(c, item, env, extra) {
  const esq = avaliar(c.leftValue, item, env, extra)
  const dir = avaliar(c.rightValue, item, env, extra)
  switch (c.operator.operation) {
    case 'equals': return esq === dir
    case 'notEquals': return esq !== dir
    case 'notEmpty': return esq !== '' && esq !== undefined && esq !== null
    case 'empty': return esq === '' || esq === undefined || esq === null
    case 'true': return esq === true || esq === 'true'
    case 'false': return esq === false || esq === 'false'
    default: throw new Error(`operação não suportada no simulador: ${c.operator.operation}`)
  }
}
const conjunto = (cond, item, env, extra) => (cond.combinator === 'or' ? cond.conditions.some((c) => condicao(c, item, env, extra)) : cond.conditions.every((c) => condicao(c, item, env, extra)))

/** `$('Nó')` das expressões (não dos nós Code): first/all/item do que o nó já produziu. */
function seletorExpr(dados, entrada) {
  return (nome) => {
    const d = dados[nome]
    if (!d) throw new Error(`Node '${nome}' hasn't been executed`)
    return {
      first: () => ({ json: d.saidas[0][0].json }),
      all: (branch = 0) => (d.saidas[branch] || []).map((i) => ({ json: i.json })),
      get item() { return { json: (entrada && entrada[0] && entrada[0].__origem[nome]) || d.saidas[0][0].json } },
    }
  }
}

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
    const extra = { $: seletorExpr(dados, entrada), $execution: { id: execucaoId } }
    for (const it of entrada) s[conjunto(no.parameters.conditions, it, env, extra) ? 0 : 1].push(it)
    return s
  }
  if (t === 'n8n-nodes-base.httpRequest') {
    // HTTP Request v4 (como nos workflows do Control iD): resposta objeto → 1 item; lista → 1 item por elemento;
    // escalar → {data: valor}; vazio (204) → {}. Erro HTTP → exceção (ou item {error} com onError = continueRegularOutput).
    const p = no.parameters
    const out = []
    for (const it of entrada) {
      const c = { $json: it.json, $env: env, $: seletorExpr(dados, [it]), $execution: { id: execucaoId } }
      const url = avaliarParametro(p.url, c)
      const headers = {}
      for (const h of (p.headerParameters && p.headerParameters.parameters) || []) headers[h.name] = String(avaliarParametro(h.value, c))
      let corpo
      if (p.sendBody) corpo = p.specifyBody === 'json' ? avaliarParametro(p.jsonBody, c) : undefined
      const tentativas = no.retryOnFail ? no.maxTries || 3 : 1
      let resposta
      let erro = null
      for (let i = 1; i <= tentativas; i++) {
        try {
          ctx.http?.push({ method: p.method || 'GET', url })
          const r = await fetch(url, {
            method: p.method || 'GET', headers,
            body: corpo === undefined ? undefined : typeof corpo === 'string' ? corpo : JSON.stringify(corpo),
            signal: AbortSignal.timeout((p.options && p.options.timeout) || 60000),
          })
          const texto = await r.text()
          if (r.status >= 400) throw Object.assign(new Error(`${r.status} - ${texto.slice(0, 300)}`), { httpCode: r.status })
          resposta = texto ? JSON.parse(texto) : null
          erro = null
          break
        } catch (e) {
          erro = e
          if (e.httpCode && e.httpCode < 500 && e.httpCode !== 429) break
          if (i < tentativas) await new Promise((ok) => setTimeout(ok, ctx.esperaRetentativaMs ?? 50))
        }
      }
      if (erro) {
        if (no.onError === 'continueRegularOutput') { out.push({ json: { error: { message: erro.message } }, __origem: it.__origem }); continue }
        throw erro
      }
      if (Array.isArray(resposta)) for (const j of resposta) out.push({ json: j, __origem: it.__origem })
      else if (resposta === null || resposta === undefined) out.push({ json: {}, __origem: it.__origem })
      else if (typeof resposta !== 'object') out.push({ json: { data: resposta }, __origem: it.__origem })
      else out.push({ json: resposta, __origem: it.__origem })
    }
    if (!out.length && no.alwaysOutputData) out.push({ json: {} })
    return [out]
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
