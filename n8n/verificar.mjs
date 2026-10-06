#!/usr/bin/env node
// Verifica os workflows N8N do repositório (todos os n8n/**/workflows/*.json, inclusive os do Control iD).
// Uso: `npm run n8n:verificar` (ou `node n8n/verificar.mjs`). Sai com código 1 se houver erro.
//      `node n8n/verificar.mjs --atualizar` reescreve as cópias `// @lib` desatualizadas (só em zig/ e comum/, do n8n-2;
//      as de controlid/ são só apontadas — o dono atualiza).
//
// Confere, para cada arquivo:
//  1. JSON válido, com `name`, `nodes[]`, `connections{}`;
//  2. nome começando com "MDG · " (e o nome exato do contrato §12.3 para os arquivos conhecidos); nomes únicos entre arquivos;
//  3. nós com name/type/typeVersion/position/parameters, nomes de nó únicos;
//  4. conexões: origem e destinos existem; todo nó (fora notas) é alcançável a partir de um gatilho;
//  5. gatilho esperado presente (Execute Workflow Trigger / Schedule com o intervalo do contrato / Error Trigger);
//  6. cópias de libs: cada linha `// @lib <caminho>` num nó Code é seguida do conteúdo de n8n/<caminho> sem as palavras `export`;
//  7. nenhum segredo fixo: JWT/chaves, `Authorization`/`apikey` literais, credenciais embutidas, URL de projeto Supabase,
//     token/senha dos mocks, `pinData` com dados.

import { readFileSync, writeFileSync, readdirSync, existsSync, statSync } from 'node:fs'
import { join, relative, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const N8N = dirname(fileURLToPath(import.meta.url))
const ATUALIZAR = process.argv.includes('--atualizar')
const DONO_N2 = (rel) => rel.startsWith('zig/') || rel.startsWith('comum/')

const T = {
  subfluxo: 'n8n-nodes-base.executeWorkflowTrigger',
  agenda: 'n8n-nodes-base.scheduleTrigger',
  erro: 'n8n-nodes-base.errorTrigger',
}
const GATILHOS = new Set([T.subfluxo, T.agenda, T.erro, 'n8n-nodes-base.manualTrigger', 'n8n-nodes-base.webhook', 'n8n-nodes-base.cron'])

/** Contrato §12.3: arquivo → nome e gatilho. `agenda` = conferência extra do Schedule. */
const ESPERADOS = {
  'controlid/workflows/controlid-importar-usuarios.json': { nome: 'MDG · Control iD · Importar usuários', gatilho: T.subfluxo },
  'controlid/workflows/controlid-importar-batidas.json': { nome: 'MDG · Control iD · Importar batidas', gatilho: T.subfluxo },
  'controlid/workflows/controlid-exportar-usuarios.json': { nome: 'MDG · Control iD · Exportar funcionários', gatilho: T.subfluxo },
  'zig/workflows/zig-importar.json': { nome: 'MDG · Zig · Importar', gatilho: T.subfluxo },
  'comum/workflows/sincronizar-agora.json': { nome: 'MDG · Sincronizar agora (fila)', gatilho: T.agenda, agenda: { field: 'minutes', minutesInterval: 1 } },
  'comum/workflows/agendador.json': { nome: 'MDG · Agendador', gatilho: T.agenda, agenda: { field: 'minutes', minutesInterval: 15 } },
  'comum/workflows/rotina-diaria.json': { nome: 'MDG · Rotina diária', gatilho: T.agenda, agenda: { field: 'cronExpression', expression: '30 5 * * *' } },
  'comum/workflows/exportar-fechamento.json': { nome: 'MDG · Exportar fechamento CSV', gatilho: T.subfluxo },
  'comum/workflows/erros.json': { nome: 'MDG · Tratador de erros', gatilho: T.erro },
}

/** Padrões de segredo. Valores dentro de expressões N8N (`={{ ... }}`) são permitidos. */
const SEGREDOS = [
  [/eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/, 'JWT (chave anon/service_role?)'],
  [/\bsb_(secret|publishable)_[A-Za-z0-9_-]{10,}/, 'chave do Supabase'],
  [/\bsk-[A-Za-z0-9]{20,}/, 'chave de API'],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, 'chave privada'],
  [/https:\/\/[a-z0-9]{20}\.supabase\.co/, 'URL de projeto Supabase fixa (use $env.SUPABASE_URL)'],
  [/\btoken-mock\b/, 'token do mock da Zig fixo no workflow'],
  [/\bsessao(-rep)?-mock\b/, 'sessão do mock do Control iD fixa no workflow'],
  [/\bgh[pousr]_[A-Za-z0-9]{30,}/, 'token do GitHub'],
  [/\bxox[abposr]-[A-Za-z0-9-]{10,}/, 'token do Slack'],
]
const CABECALHOS_SENSIVEIS = /^(authorization|apikey|x-api-key|api-key|token|x-token)$/i
const CHAVES_SENSIVEIS = /^(password|senha|token|apikey|api_key|secret|segredo|service_role_key|chave)$/i

const erros = []
const avisos = []
const erro = (arq, msg) => erros.push(`${arq}: ${msg}`)
const aviso = (arq, msg) => avisos.push(`${arq}: ${msg}`)

function listarWorkflows(dir) {
  const saida = []
  for (const nome of readdirSync(dir)) {
    const p = join(dir, nome)
    if (nome === 'node_modules' || nome === 'mocks') continue
    if (statSync(p).isDirectory()) saida.push(...listarWorkflows(p))
    else if (nome.endsWith('.json') && relative(N8N, p).split('/').includes('workflows')) saida.push(p)
  }
  return saida.sort()
}

/** Conteúdo de uma lib como deve aparecer no nó Code (sem `export`, fim de linha \n, sem espaços finais). */
function libTransformada(rel) {
  const p = join(N8N, rel)
  if (!existsSync(p)) return null
  return readFileSync(p, 'utf8').replace(/\r\n/g, '\n').replace(/^export /gm, '').trimEnd()
}

/** Confere (e opcionalmente corrige) as cópias `// @lib` de um código. Retorna { codigo, problemas[] }. */
function conferirLibs(codigo) {
  const problemas = []
  const texto = codigo.replace(/\r\n/g, '\n')
  const re = /^\/\/ @lib (\S+)[ \t]*$/gm
  const marcas = [...texto.matchAll(re)]
  if (!marcas.length) return { codigo, problemas, alterado: false }
  let novo = ''
  let cursor = 0
  for (let k = 0; k < marcas.length; k++) {
    const m = marcas[k]
    const rel = m[1]
    const inicio = m.index + m[0].length + 1 // depois da quebra de linha
    const esperado = libTransformada(rel)
    novo += texto.slice(cursor, inicio)
    if (esperado === null) {
      problemas.push(`lib "${rel}" não existe`)
      cursor = inicio
      continue
    }
    const atual = texto.slice(inicio)
    if (atual.startsWith(esperado)) {
      novo += esperado
      cursor = inicio + esperado.length
      continue
    }
    // diferença: onde termina a cópia atual? até a próxima marca @lib ou até a linha "// ----" de uso, ou fim
    const prox = k + 1 < marcas.length ? marcas[k + 1].index : texto.indexOf('\n// ----', inicio)
    const fim = prox > inicio ? prox : texto.length
    const linhaDif = (() => {
      const a = atual.split('\n')
      const b = esperado.split('\n')
      for (let i = 0; i < b.length; i++) if (a[i] !== b[i]) return i + 1
      return b.length
    })()
    problemas.push(`cópia de "${rel}" diferente da lib (1ª diferença na linha ${linhaDif} da lib) — rode a cópia de novo`)
    novo += esperado + '\n'
    cursor = fim
    while (texto[cursor] === '\n' && texto[cursor + 1] === '\n') cursor++
  }
  novo += texto.slice(cursor)
  return { codigo: novo, problemas, alterado: novo !== texto }
}

function procurarSegredos(arq, valor, caminho) {
  if (typeof valor === 'string') {
    const expressao = valor.startsWith('=')
    for (const [re, desc] of SEGREDOS) {
      if (re.test(valor)) erro(arq, `possível segredo fixo (${desc}) em ${caminho}`)
    }
    if (!expressao && /^Bearer\s+[A-Za-z0-9._-]{12,}$/.test(valor.trim())) erro(arq, `Authorization fixo em ${caminho}`)
    return
  }
  if (Array.isArray(valor)) return valor.forEach((v, i) => procurarSegredos(arq, v, `${caminho}[${i}]`))
  if (valor && typeof valor === 'object') {
    // cabeçalhos do HTTP Request: {name, value}
    if (typeof valor.name === 'string' && CABECALHOS_SENSIVEIS.test(valor.name) && typeof valor.value === 'string' && valor.value && !valor.value.startsWith('=')) {
      erro(arq, `cabeçalho "${valor.name}" com valor fixo em ${caminho} (use expressão com $env)`)
    }
    for (const [k, v] of Object.entries(valor)) {
      if (k === 'jsCode' || k === 'content') { procurarSegredosCodigo(arq, v, `${caminho}.${k}`); continue }
      if (CHAVES_SENSIVEIS.test(k) && typeof v === 'string' && v && !v.startsWith('=')) erro(arq, `campo "${k}" com valor fixo em ${caminho}`)
      procurarSegredos(arq, v, `${caminho}.${k}`)
    }
  }
}
function procurarSegredosCodigo(arq, codigo, caminho) {
  if (typeof codigo !== 'string') return
  for (const [re, desc] of SEGREDOS) if (re.test(codigo)) erro(arq, `possível segredo fixo (${desc}) em ${caminho}`)
  const atrib = codigo.match(/\b(SUPABASE_SERVICE_ROLE_KEY|service_role|apikey|senha|password|token)\s*[:=]\s*['"`][A-Za-z0-9._\-]{16,}['"`]/i)
  if (atrib) erro(arq, `atribuição de segredo literal no código (${atrib[0].slice(0, 40)}…) em ${caminho}`)
}

function verificarArquivo(p, nomesVistos) {
  const arq = relative(N8N, p)
  let wf
  const bruto = readFileSync(p, 'utf8')
  try {
    wf = JSON.parse(bruto)
  } catch (e) {
    erro(arq, `JSON inválido: ${e.message}`)
    return
  }
  if (!wf || typeof wf !== 'object' || Array.isArray(wf)) return erro(arq, 'raiz do JSON deve ser um objeto de workflow')
  if (typeof wf.name !== 'string' || !wf.name.startsWith('MDG · ')) erro(arq, `nome "${wf.name}" deve começar com "MDG · "`)
  const esperado = ESPERADOS[arq]
  if (esperado && wf.name !== esperado.nome) erro(arq, `nome deve ser "${esperado.nome}" (contrato §12.3), está "${wf.name}"`)
  if (nomesVistos.has(wf.name)) erro(arq, `nome "${wf.name}" repetido (também em ${nomesVistos.get(wf.name)})`)
  nomesVistos.set(wf.name, arq)
  if (!Array.isArray(wf.nodes) || !wf.nodes.length) return erro(arq, 'sem nodes[]')
  if (!wf.connections || typeof wf.connections !== 'object') return erro(arq, 'sem connections{}')
  if (wf.settings && wf.settings.executionOrder && wf.settings.executionOrder !== 'v1') aviso(arq, 'settings.executionOrder diferente de "v1"')
  if (wf.pinData && Object.keys(wf.pinData).length) erro(arq, 'pinData com dados fixados (pode vazar dados reais) — limpe antes de exportar')
  if (wf.active === true) aviso(arq, 'exportado ativo; prefira importar desativado e ativar na ordem do README')

  const porNome = new Map()
  for (const [i, n] of wf.nodes.entries()) {
    const onde = `nó #${i}${n && n.name ? ` "${n.name}"` : ''}`
    if (!n || typeof n.name !== 'string' || !n.name) { erro(arq, `${onde} sem name`); continue }
    if (porNome.has(n.name)) erro(arq, `nome de nó repetido: "${n.name}"`)
    porNome.set(n.name, n)
    if (typeof n.type !== 'string' || !n.type) erro(arq, `${onde} sem type`)
    if (typeof n.typeVersion !== 'number') erro(arq, `${onde} sem typeVersion numérico`)
    if (!Array.isArray(n.position) || n.position.length !== 2) erro(arq, `${onde} sem position [x, y]`)
    if (!n.parameters || typeof n.parameters !== 'object') erro(arq, `${onde} sem parameters`)
    if (n.credentials) {
      for (const [tipo, c] of Object.entries(n.credentials)) {
        if (c && typeof c === 'object' && Object.keys(c).some((k) => !['id', 'name'].includes(k))) erro(arq, `${onde}: credencial "${tipo}" com dados embutidos`)
      }
    }
    if (n.type === 'n8n-nodes-base.code') {
      const campo = typeof n.parameters?.jsCode === 'string' ? 'jsCode' : null
      if (!campo) { if (n.parameters?.language !== 'python') erro(arq, `${onde}: nó Code sem jsCode`); continue }
      const r = conferirLibs(n.parameters.jsCode)
      for (const prob of r.problemas) erro(arq, `${onde}: ${prob}`)
      if (r.alterado && ATUALIZAR && DONO_N2(arq)) n.parameters.jsCode = r.codigo
    }
  }

  // conexões
  const destinos = new Map()
  for (const [origem, tipos] of Object.entries(wf.connections)) {
    if (!porNome.has(origem)) erro(arq, `conexão parte de nó inexistente "${origem}"`)
    for (const [tipo, saidas] of Object.entries(tipos || {})) {
      if (!Array.isArray(saidas)) { erro(arq, `conexões de "${origem}".${tipo} devem ser lista`); continue }
      saidas.forEach((lista, idx) => {
        for (const c of lista || []) {
          if (!c || !porNome.has(c.node)) erro(arq, `conexão "${origem}"[${idx}] aponta para nó inexistente "${c && c.node}"`)
          else {
            if (!destinos.has(origem)) destinos.set(origem, new Set())
            destinos.get(origem).add(c.node)
          }
          if (c && c.type && c.type !== tipo) aviso(arq, `conexão "${origem}" → "${c.node}" com type "${c.type}" em lista "${tipo}"`)
        }
      })
    }
  }

  // gatilhos
  const gatilhos = wf.nodes.filter((n) => GATILHOS.has(n.type) || /Trigger$/.test(n.type || ''))
  if (!gatilhos.length) erro(arq, 'nenhum gatilho (trigger) no workflow')
  if (esperado) {
    const g = wf.nodes.filter((n) => n.type === esperado.gatilho)
    if (!g.length) erro(arq, `falta o gatilho ${esperado.gatilho} (contrato §12.3)`)
    if (esperado.agenda && g.length) {
      const intervalos = g.flatMap((n) => n.parameters?.rule?.interval || [])
      const ok = intervalos.some((i) => Object.entries(esperado.agenda).every(([k, v]) => i[k] === v))
      if (!ok) erro(arq, `agenda deve ser ${JSON.stringify(esperado.agenda)}, está ${JSON.stringify(intervalos)}`)
    }
  }
  // alcançabilidade
  const vistos = new Set()
  const fila = gatilhos.map((g) => g.name)
  while (fila.length) {
    const n = fila.shift()
    if (vistos.has(n)) continue
    vistos.add(n)
    for (const d of destinos.get(n) || []) fila.push(d)
  }
  for (const n of wf.nodes) {
    if (n.type === 'n8n-nodes-base.stickyNote' || vistos.has(n.name)) continue
    erro(arq, `nó "${n.name}" não é alcançável a partir de nenhum gatilho`)
  }

  procurarSegredos(arq, { ...wf, pinData: undefined }, 'workflow')

  if (ATUALIZAR && DONO_N2(arq)) {
    const novo = JSON.stringify(wf, null, 2) + '\n'
    if (novo !== bruto) {
      writeFileSync(p, novo)
      console.log(`atualizado: ${arq}`)
    }
  }
  return wf
}

const arquivos = listarWorkflows(N8N)
const nomes = new Map()
for (const p of arquivos) verificarArquivo(p, nomes)
for (const arq of Object.keys(ESPERADOS)) if (!existsSync(join(N8N, arq))) erro(arq, 'arquivo obrigatório (contrato §12.3) não encontrado')

// Com --atualizar, a correção já foi gravada: confere de novo para não mascarar outros erros.
if (ATUALIZAR) {
  erros.length = 0
  avisos.length = 0
  const n2 = new Map()
  for (const p of arquivos) verificarArquivo(p, n2)
  for (const arq of Object.keys(ESPERADOS)) if (!existsSync(join(N8N, arq))) erro(arq, 'arquivo obrigatório (contrato §12.3) não encontrado')
}

for (const a of avisos) console.log(`aviso  ${a}`)
for (const e of erros) console.log(`ERRO   ${e}`)
console.log(`\n${arquivos.length} workflow(s) verificados: ${erros.length} erro(s), ${avisos.length} aviso(s).`)
if (erros.length) process.exit(1)
