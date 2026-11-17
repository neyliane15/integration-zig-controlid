// Integração RHiD (nuvem da Control iD) pela API oficial — docs/referencias/rhid-swagger.json e docs/CONTRATO-ADENDO-rhid.md.
// Funções puras, sem import. Copiada no nó Code do workflow "MDG · RHiD · Importar" com `// @lib rhid/lib/rhid.mjs`,
// logo depois de `// @lib controlid/lib/afd.mjs` (o leitor de AFD `lerAfd` entra por `deps.lerAfd`) e de
// `// @lib comum/lib/supabase.mjs` (transporte, RPC e sync_execucoes). Conferida por `npm run n8n:verificar`.
//
// Por que RHiD: o relógio da loja (iDClass, Portaria 671) não é alcançável pela rede, mas sincroniza com o RHiD; a API do
// RHiD devolve as pessoas e o AFD 671 de cada equipamento.
//
//   POST {base}/login  {email, password, domain?}           → {accessToken}   (demais: Authorization: Bearer <token>; 401 → novo login)
//   GET  {base}/person                                       → {totalRecords, records: [PersonDTO]} (sem paginação de verdade)
//   GET  {base}/device                                       → {totalRecords, records: [DeviceDTO]} (model 1=REP-C, 2=REP-A, 3=Outros, 5=REP-P)
//   GET  {base}/report/afd/download671?idEquipamento=&dataIni=&dataFinal=&nsrInicial=&limit=   → texto AFD 671 (≤ 90 dias, limit ≤ 50000)
//        REP-P: idEquipamento = idCompany + 99000000
//   GET  {base}/report/afd_coletor_marcacao/download671?…   → AFD das marcações do coletor do REP-P (mesmas regras)
//
// Integração tipo 'rhid':
//   segredos   { email, senha, dominio? }   (crie no RHiD um usuário só para a integração, com leitura de pessoas e relatórios)
//   parametros { equipamentos: [] (ids; vazio = REPs do cliente + REP-P), incluir_rep_p: true, dias_retroativos: 7,
//                importar_pessoas: true, url_base?: (padrão RHID_BASE_PADRAO ou variável RHID_BASE_URL), limite_afd?: 50000 }
//   cursor     { nsr_por_equipamento: { "<chave>": ultimo_nsr } }   chave = id do equipamento; coletor do REP-P = "c<id>"
//              horarios_em: último envio dos horários previstos (§R.9; parametros importar_horarios, horarios_intervalo_minutos,
//              dias_horarios)
//   GET  {base}/apuracao_ponto?idPerson=&dataIni=&dataFinal=  → string JSON: um objeto por dia (horasUteis, folga, isHoliday…)
// Nunca registra senha nem token (nem em mensagem de erro, nem em sync_execucoes.detalhes).

export const RHID_BASE_PADRAO = 'https://www.rhid.com.br/v2/api.svc'
export const RHID_MAX_DIAS = 90
export const RHID_LIMITE_AFD = 50000
export const RHID_DESLOCAMENTO_REP_P = 99000000
export const RHID_TAMANHO_LOTE = 1000
/** Modelos do RHiD que geram AFD por id próprio (1 = REP-C, 2 = REP-A). REP-P (5) usa idCompany + 99000000. */
export const RHID_MODELOS_REP = [1, 2]

function preenchidoRhid(v) {
  return v !== undefined && v !== null && !(typeof v === 'string' && v.trim() === '')
}

export function somarDiasRhid(iso, n) {
  return new Date(Date.parse(iso + 'T00:00:00Z') + n * 86400000).toISOString().slice(0, 10)
}

function dataValidaRhid(iso) {
  if (typeof iso !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return false
  const d = new Date(iso + 'T00:00:00Z')
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === iso
}

function inteiroRhid(v, padrao, min, max) {
  const n = v === undefined || v === null || v === '' ? padrao : Math.trunc(Number(v))
  if (!Number.isFinite(n)) return padrao
  return Math.max(min, Math.min(max, n))
}

/** Confere tipo e credenciais; devolve a URL base (sem barra final). */
export function validarConfigRhid(config, baseVariavel) {
  if (!config || config.tipo !== 'rhid') throw new Error('Tipo de integração incompatível')
  const s = config.segredos || {}
  if (!preenchidoRhid(s.email) || !preenchidoRhid(s.senha)) {
    throw new Error('Credencial do RHiD não configurada (Integrações → RHiD: e-mail e senha do usuário de integração)')
  }
  const p = config.parametros || {}
  const base = (preenchidoRhid(p.url_base) && p.url_base) || (preenchidoRhid(baseVariavel) && baseVariavel) || RHID_BASE_PADRAO
  if (!/^https?:\/\//.test(String(base))) throw new Error(`URL base do RHiD inválida: ${base}`)
  return String(base).replace(/\/+$/, '')
}

/** O que esta execução faz: pessoas (tudo/funcionarios, se importar_pessoas) e/ou batidas (tudo/batidas). */
export function planoRhid(entrada, config) {
  const escopo = (entrada && entrada.escopo) || 'tudo'
  const p = (config && config.parametros) || {}
  return {
    pessoas: (escopo === 'tudo' && p.importar_pessoas !== false) || escopo === 'funcionarios',
    batidas: escopo === 'tudo' || escopo === 'batidas',
  }
}

/** Requisição de login (o corpo leva a senha: nunca registrar `req`). */
export function requisicaoLoginRhid(base, segredos, timeoutMs) {
  const corpo = { email: String(segredos.email).trim(), password: String(segredos.senha) }
  if (preenchidoRhid(segredos.dominio)) corpo.domain = String(segredos.dominio).trim()
  return { method: 'POST', url: `${base}/login`, headers: { 'Content-Type': 'application/json', Accept: 'application/json' }, corpo, timeoutMs: timeoutMs || 60000 }
}

function corpoJsonRhid(corpo) {
  if (typeof corpo === 'string') {
    const t = corpo.trim()
    if (t.startsWith('{') || t.startsWith('[') || t.startsWith('"')) {
      try { return JSON.parse(t) } catch (e) { return corpo }
    }
  }
  return corpo
}

/** accessToken da resposta do login; erros do RHiD viram mensagem clara (sem ecoar credenciais). */
export function tokenDoLoginRhid(corpo) {
  const c = corpoJsonRhid(corpo) || {}
  if (c.expiredPassword === true) throw new Error('RHiD: a senha do usuário de integração expirou — troque no RHiD e atualize em Integrações')
  if (c.customerBlocked === true) throw new Error('RHiD: cliente bloqueado no RHiD')
  if (c.isPerson === true) throw new Error('RHiD: o login é de um colaborador (Person); use um usuário operador com leitura de pessoas e relatórios')
  if (!preenchidoRhid(c.accessToken)) throw new Error(`RHiD: login sem token${c.error ? ` (${String(c.error).slice(0, 120)})` : ''}`)
  return String(c.accessToken)
}

export function cabecalhosRhid(token) {
  return { Authorization: `Bearer ${token}`, Accept: 'application/json, text/plain, */*' }
}

/** URL com query (valores vazios saem). */
export function urlRhid(base, caminho, params) {
  const qs = Object.entries(params || {})
    .filter(([, v]) => v !== undefined && v !== null && v !== '')
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
    .join('&')
  return `${base}${caminho}${qs ? '?' + qs : ''}`
}

/** `records` de PersonResult/DeviceResult (aceita a lista na raiz e corpo em texto JSON). */
export function registrosRhid(corpo, rotulo) {
  const c = corpoJsonRhid(corpo)
  if (Array.isArray(c)) return c
  if (c && typeof c === 'object' && Array.isArray(c.records)) return c.records
  if (c && typeof c === 'object' && (c.error || c.code)) throw new Error(`RHiD ${rotulo}: ${String(c.error || c.code).slice(0, 200)}`)
  throw new Error(`RHiD ${rotulo}: resposta sem "records"`)
}

/** Texto do AFD: a API declara application/json, então o texto pode vir como string JSON ("…"). */
export function textoAfdRhid(corpo) {
  if (corpo === null || corpo === undefined) return ''
  if (typeof corpo === 'string') {
    const t = corpo.trim()
    if (t.startsWith('"')) {
      try { const v = JSON.parse(t); if (typeof v === 'string') return v } catch (e) { /* texto cru */ }
    }
    if (t.startsWith('{')) {
      const v = corpoJsonRhid(t)
      if (v && typeof v === 'object') throw new Error(`RHiD AFD: ${String(v.error || v.message || JSON.stringify(v)).slice(0, 200)}`)
    }
    return corpo
  }
  if (typeof corpo === 'object') {
    if (typeof corpo.data === 'string') return corpo.data
    throw new Error(`RHiD AFD: ${String(corpo.error || corpo.message || JSON.stringify(corpo)).slice(0, 200)}`)
  }
  return String(corpo)
}

/** idCompany distintos (pessoas e equipamentos), em ordem. */
export function empresasRhid(pessoas, dispositivos) {
  const ids = new Set()
  for (const p of pessoas || []) if (p && Number(p.idCompany) > 0) ids.add(Number(p.idCompany))
  for (const d of dispositivos || []) {
    if (!d) continue
    if (Number(d.linkedCompanyId) > 0) ids.add(Number(d.linkedCompanyId))
    for (const c of d.listOfLinkedCompanyIds || []) if (Number(c) > 0) ids.add(Number(c))
  }
  return [...ids].sort((a, b) => a - b)
}

/**
 * Equipamentos a baixar: [{chave, id, nome, rota: 'afd' | 'coletor', automatico}].
 * `parametros.equipamentos` com ids → só esses (id ≥ 99000000 = REP-P: também o coletor, se incluir_rep_p).
 * Vazio → REPs do cliente (model 1/2) e, com incluir_rep_p, o REP-P de cada idCompany (AFD + coletor).
 */
export function alvosRhid(dispositivos, parametros, empresas) {
  const p = parametros || {}
  const repP = p.incluir_rep_p !== false
  const lista = []
  const vistos = new Set()
  const add = (id, nome, rota, automatico) => {
    const chave = rota === 'coletor' ? `c${id}` : String(id)
    if (vistos.has(chave)) return
    vistos.add(chave)
    lista.push({ chave, id: Number(id), nome, rota, automatico })
  }
  const nomes = new Map((dispositivos || []).filter(Boolean).map((d) => [Number(d.id), d.name || d.serial || `Equipamento ${d.id}`]))
  const explicitos = (Array.isArray(p.equipamentos) ? p.equipamentos : [])
    .map((x) => (x && typeof x === 'object' ? x.id : x))
    .map((x) => Math.trunc(Number(String(x).trim())))
    .filter((x) => Number.isFinite(x) && x > 0)
  if (explicitos.length) {
    for (const id of explicitos) {
      const ehRepP = id >= RHID_DESLOCAMENTO_REP_P
      const nome = nomes.get(id) || (ehRepP ? `REP-P (empresa ${id - RHID_DESLOCAMENTO_REP_P})` : `Equipamento ${id}`)
      add(id, nome, 'afd', false)
      if (ehRepP && repP) add(id, `${nome} · coletor`, 'coletor', false)
    }
    return lista
  }
  for (const d of dispositivos || []) {
    if (d && RHID_MODELOS_REP.includes(Number(d.model)) && Number(d.id) > 0) add(Number(d.id), nomes.get(Number(d.id)), 'afd', false)
  }
  if (repP) {
    for (const c of empresas || []) {
      const id = RHID_DESLOCAMENTO_REP_P + Number(c)
      add(id, `REP-P (empresa ${c})`, 'afd', true)
      add(id, `REP-P (empresa ${c}) · coletor`, 'coletor', true)
    }
  }
  return lista
}

/**
 * Janela e NSR inicial de um equipamento. `hoje` = dia de trabalho atual; o fim vai até hoje + 1 (batidas depois da meia-noite).
 *   pedido com data_inicio/data_fim → as datas pedidas (fim + 1), sem NSR (reimportação idempotente)
 *   com cursor                      → nsrInicial = cursor + 1, janela máxima (90 dias até hoje + 1)
 *   sem cursor                      → [hoje − dias_retroativos, hoje + 1]
 */
export function janelaRhid(entrada, config, ultimoNsr) {
  const hoje = config && config.dia_trabalho_atual
  if (!dataValidaRhid(hoje)) throw new Error('Configuração sem dia_trabalho_atual')
  const p = (config && config.parametros) || {}
  const fimPadrao = somarDiasRhid(hoje, 1)
  let ini = entrada && entrada.data_inicio
  let fim = entrada && entrada.data_fim
  if (ini || fim) {
    ini = ini || fim
    fim = fim || ini
    if (!dataValidaRhid(ini) || !dataValidaRhid(fim) || ini > fim) throw new Error(`Período inválido: ${ini} a ${fim}`)
    fim = somarDiasRhid(fim, 1)
    if (somarDiasRhid(ini, RHID_MAX_DIAS - 1) < fim) ini = somarDiasRhid(fim, -(RHID_MAX_DIAS - 1))
    return { dataIni: ini, dataFinal: fim, nsrInicial: null, modo: 'periodo' }
  }
  if (ultimoNsr !== undefined && ultimoNsr !== null && Number.isFinite(Number(ultimoNsr))) {
    return { dataIni: somarDiasRhid(fimPadrao, -(RHID_MAX_DIAS - 1)), dataFinal: fimPadrao, nsrInicial: Math.trunc(Number(ultimoNsr)) + 1, modo: 'cursor' }
  }
  const retro = inteiroRhid(p.dias_retroativos, 7, 0, RHID_MAX_DIAS - 2)
  return { dataIni: somarDiasRhid(hoje, -retro), dataFinal: fimPadrao, nsrInicial: null, modo: 'retroativo' }
}

/** Requisição do AFD 671 de um equipamento (rota afd ou coletor). */
export function requisicaoAfdRhid(base, token, alvo, janela, limite, timeoutMs) {
  const caminho = alvo.rota === 'coletor' ? '/report/afd_coletor_marcacao/download671' : '/report/afd/download671'
  const params = { idEquipamento: alvo.id, dataIni: janela.dataIni, dataFinal: janela.dataFinal, nsrInicial: janela.nsrInicial, limit: limite }
  return { method: 'GET', url: urlRhid(base, caminho, params), headers: cabecalhosRhid(token), texto: true, timeoutMs: timeoutMs || 120000 }
}

export function lotesRhid(lista, tamanho) {
  const t = Math.max(1, Math.floor(tamanho || RHID_TAMANHO_LOTE))
  const saida = []
  for (let i = 0; i < (lista || []).length; i += t) saida.push(lista.slice(i, i + t))
  return saida
}

/**
 * Sessão autenticada: `{ base, obter(caminho, params, opcoes) → corpo, texto(req) }`, com novo login (uma vez) no 401.
 * deps: { requisitar(req, opcoes) → {status, corpo, tentativas}, baseUrl?, tentativas = 3, esperaMs = 5000, dormir?, timeoutMs }
 */
export async function abrirSessaoRhid(config, deps) {
  const base = validarConfigRhid(config, deps.baseUrl)
  const opcoes = (rotulo) => ({ tentativas: deps.tentativas ?? 3, esperaMs: deps.esperaMs ?? 5000, dormir: deps.dormir, rotulo })
  const sessao = { base, token: null, logins: 0, tentativasMax: 1 }
  const logar = async () => {
    const r = await deps.requisitar(requisicaoLoginRhid(base, config.segredos, deps.timeoutMs), opcoes('RHiD login'))
    sessao.logins++
    sessao.tentativasMax = Math.max(sessao.tentativasMax, r.tentativas || 1)
    sessao.token = tokenDoLoginRhid(r.corpo)
  }
  sessao.chamar = async (montar, rotulo) => {
    if (!sessao.token) await logar()
    let renovou = false
    for (;;) {
      try {
        const r = await deps.requisitar(montar(sessao.token), opcoes(rotulo))
        sessao.tentativasMax = Math.max(sessao.tentativasMax, r.tentativas || 1)
        return r.corpo
      } catch (e) {
        if (e && e.status === 401 && !renovou) { renovou = true; await logar(); continue }
        throw e
      }
    }
  }
  // RHiD real: GET /device sem start/length responde HTTP 500, e length > 100 também (a spec diz que são opcionais).
  // Lista sempre paginada de 100 em 100 até vir menos que uma página ou atingir totalRecords.
  sessao.listar = async (caminho, rotulo) => {
    const POR_PAGINA = 100
    const todos = []
    for (let pagina = 0; pagina < 200; pagina++) {
      const corpo = await sessao.chamar((token) => ({ method: 'GET', url: urlRhid(base, caminho, { start: pagina * POR_PAGINA, length: POR_PAGINA }), headers: cabecalhosRhid(token), timeoutMs: deps.timeoutMs || 120000 }), rotulo)
      const registros = registrosRhid(corpo, rotulo)
      todos.push(...registros)
      const c = corpoJsonRhid(corpo)
      const total = Number(c && typeof c === 'object' ? c.totalRecords : NaN)
      if (registros.length < POR_PAGINA || (Number.isFinite(total) && todos.length >= total)) break
    }
    return todos
  }
  await logar()
  return sessao
}

/** Pessoas do RHiD → `ingestao_rhid_pessoas` (snapshot). Lista vazia → erro (nada é marcado como removido). */
export async function importarPessoasRhid(config, sessao, deps) {
  const pessoas = sessao.pessoas || (sessao.pessoas = await sessao.listar('/person', 'pessoas'))
  if (!pessoas.length) throw new Error('RHiD devolveu nenhuma pessoa (confira se o usuário de integração pode ler Pessoas)')
  const enxutas = pessoas.map((x) => ({ id: x.id, cpf: x.cpf, pis: x.pis, name: x.name, socialName: x.socialName, registration: x.registration, status: x.status, idCompany: x.idCompany }))
  const ret = (await deps.rpc('ingestao_rhid_pessoas', { p_integracao: config.integracao_id, p_pessoas: enxutas })) || {}
  return {
    status: 'sucesso',
    lidos: pessoas.length,
    gravados: Number(ret.gravados) || 0,
    ignorados: Number(ret.ignorados) || 0,
    detalhes: { pessoas: pessoas.length, ingestao: ret, logins: sessao.logins },
    tentativas: sessao.tentativasMax,
  }
}

/**
 * Batidas: lista equipamentos, baixa o AFD 671 de cada um (do cursor em diante), lê com `deps.lerAfd` e grava em lotes
 * (`ingestao_rhid_batidas`, que atualiza o cursor do equipamento). Equipamento automático (REP-P) com erro 4xx só vira aviso.
 * deps: { rpc, lerAfd, resumoAfd?, limite?, tamanhoLote?, maxPaginas = 20 }
 */
export async function importarBatidasRhid(config, entrada, sessao, deps) {
  if (typeof deps.lerAfd !== 'function') throw new Error('lerAfd indisponível (copie controlid/lib/afd.mjs no nó)')
  const p = config.parametros || {}
  const cursor = (config.cursor && config.cursor.nsr_por_equipamento) || {}
  const limite = inteiroRhid(p.limite_afd ?? deps.limite, RHID_LIMITE_AFD, 1, RHID_LIMITE_AFD)
  const maxPaginas = deps.maxPaginas ?? 20
  const explicitos = Array.isArray(p.equipamentos) && p.equipamentos.length > 0
  const dispositivos = explicitos ? [] : await sessao.listar('/device', 'equipamentos')
  let empresas = []
  if (!explicitos && p.incluir_rep_p !== false) {
    if (!sessao.pessoas) sessao.pessoas = await sessao.listar('/person', 'pessoas')
    empresas = empresasRhid(sessao.pessoas, dispositivos)
  }
  const alvos = alvosRhid(dispositivos, p, empresas)
  const tot = { lidos: 0, gravados: 0, ignorados: 0, duplicados: 0, sem_funcionario: 0 }
  const equipamentos = []
  const avisos = []
  const falhas = []
  for (const alvo of alvos) {
    const ultimo = cursor[alvo.chave]
    const janela = janelaRhid(entrada, config, ultimo)
    const resumo = { chave: alvo.chave, nome: alvo.nome, rota: alvo.rota, janela, paginas: 0, marcacoes: 0, gravados: 0, duplicados: 0, ignorados: 0, sem_funcionario: 0, ultimo_nsr: ultimo ?? null }
    try {
      let nsrInicial = janela.nsrInicial
      for (let pagina = 0; pagina < maxPaginas; pagina++) {
        const texto = textoAfdRhid(await sessao.chamar((token) => requisicaoAfdRhid(sessao.base, token, alvo, { ...janela, nsrInicial }, limite, deps.timeoutMs), `RHiD AFD ${alvo.chave}`))
        resumo.paginas++
        const leitura = deps.lerAfd(texto)
        const piso = janela.modo === 'cursor' && ultimo != null ? Number(ultimo) : -1
        const marcacoes = leitura.marcacoes.filter((m) => Number(m.nsr) > piso)
        resumo.marcacoes += marcacoes.length
        if (pagina === 0 && deps.resumoAfd) resumo.afd = deps.resumoAfd(leitura)
        for (const lote of lotesRhid(marcacoes, deps.tamanhoLote || RHID_TAMANHO_LOTE)) {
          const r = (await deps.rpc('ingestao_rhid_batidas', { p_integracao: config.integracao_id, p_equipamento: alvo.chave, p_marcacoes: lote })) || {}
          resumo.gravados += Number(r.gravados) || 0
          resumo.duplicados += Number(r.duplicados) || 0
          resumo.ignorados += Number(r.ignorados) || 0
          resumo.sem_funcionario += Number(r.sem_funcionario) || 0
          if (r.ultimo_nsr !== undefined && r.ultimo_nsr !== null) resumo.ultimo_nsr = Number(r.ultimo_nsr)
          if (Array.isArray(r.erros) && r.erros.length) resumo.erros = (resumo.erros || []).concat(r.erros).slice(0, 10)
        }
        // limite atingido → próxima página a partir do maior NSR lido
        const registros = leitura.marcacoes.length + leitura.ignoradas.length
        if (registros < limite || !leitura.marcacoes.length) break
        nsrInicial = Math.max(...leitura.marcacoes.map((m) => Number(m.nsr))) + 1
        if (pagina === maxPaginas - 1) avisos.push(`${alvo.nome}: parou após ${maxPaginas} páginas de ${limite} registros`)
      }
    } catch (e) {
      const status = e && e.status
      const msg = `${alvo.nome}: ${e && e.message ? e.message : String(e)}`.slice(0, 300)
      if (alvo.automatico && status >= 400 && status < 500 && status !== 401) avisos.push(msg)
      else falhas.push(msg)
      resumo.erro = msg
    }
    tot.lidos += resumo.marcacoes
    tot.gravados += resumo.gravados
    tot.duplicados += resumo.duplicados
    tot.ignorados += resumo.ignorados
    tot.sem_funcionario += resumo.sem_funcionario
    equipamentos.push(resumo)
  }
  if (!alvos.length) avisos.push('Nenhum equipamento REP encontrado no RHiD (confira parametros.equipamentos ou a permissão do usuário)')
  const errosBanco = equipamentos.flatMap((x) => x.erros || [])
  const falhou = falhas.length > 0
  if (falhou && !equipamentos.some((x) => !x.erro)) {
    const e = new Error(falhas.slice(0, 3).join(' | '))
    e.tentativas = sessao.tentativasMax
    throw e
  }
  return {
    status: falhou || errosBanco.length ? 'parcial' : 'sucesso',
    lidos: tot.lidos,
    gravados: tot.gravados,
    ignorados: tot.ignorados,
    erro: falhou ? falhas.slice(0, 3).join(' | ') : errosBanco.length ? `${errosBanco.length} marcação(ões) recusada(s) pelo banco` : null,
    detalhes: { equipamentos, duplicados: tot.duplicados, sem_funcionario: tot.sem_funcionario, avisos, logins: sessao.logins },
    tentativas: sessao.tentativasMax,
  }
}

/** CPF do RHiD (número, perde zeros à esquerda) → 11 dígitos, ou null. */
export function cpfRhid(v) {
  const d = String(v ?? '').replace(/\D/g, '')
  if (!d || /^0+$/.test(d) || d.length > 11) return null
  return d.padStart(11, '0')
}

/**
 * Horários previstos (adendo RHiD §R.9): roda junto com as batidas, no máximo a cada `horarios_intervalo_minutos`
 * (padrão 60, pelo cursor.horarios_em), ou sempre no "Sincronizar agora"/período pedido. `importar_horarios: false` desliga.
 */
export function deveImportarHorariosRhid(entrada, config, agoraMs) {
  const p = (config && config.parametros) || {}
  if (p.importar_horarios === false) return false
  if (entrada && (entrada.gatilho === 'manual' || entrada.data_inicio || entrada.data_fim)) return true
  const ultimo = Date.parse((config && config.cursor && config.cursor.horarios_em) || '')
  if (!Number.isFinite(ultimo)) return true
  const intervalo = inteiroRhid(p.horarios_intervalo_minutos, 60, 0, 24 * 60)
  return (agoraMs ?? Date.now()) - ultimo >= intervalo * 60000
}

/** Período da apuração: o pedido (≤ 90 dias, até hoje) ou [hoje − dias_horarios (padrão 40), hoje]. */
export function janelaHorariosRhid(entrada, config) {
  const hoje = config && config.dia_trabalho_atual
  if (!dataValidaRhid(hoje)) throw new Error('Configuração sem dia_trabalho_atual')
  const p = (config && config.parametros) || {}
  let ini = entrada && entrada.data_inicio
  let fim = entrada && entrada.data_fim
  if (ini || fim) {
    ini = ini || fim
    fim = fim || hoje
    if (!dataValidaRhid(ini) || !dataValidaRhid(fim) || ini > fim) throw new Error(`Período inválido: ${ini} a ${fim}`)
    if (fim > hoje) fim = hoje
    if (ini > fim) ini = fim
  } else {
    fim = hoje
    ini = somarDiasRhid(hoje, -inteiroRhid(p.dias_horarios, 40, 0, RHID_MAX_DIAS - 1))
  }
  if (somarDiasRhid(ini, RHID_MAX_DIAS - 1) < fim) ini = somarDiasRhid(fim, -(RHID_MAX_DIAS - 1))
  return { dataIni: ini, dataFinal: fim }
}

/**
 * Apuração do RHiD de uma pessoa (GET /apuracao_ponto; corpo = string JSON com um objeto por dia) → dias para
 * `ingestao_rhid_horarios`: previsto = horasUteis (0 em folga/feriado), horários de strHorarioContratualSimples
 * ("08:00-13:00\r\n13:30-15:50"), feriado = nome, saldo = saldoBancoCredDeb.
 */
export function diasApuracaoRhid(corpo, cpf, tolerancias) {
  const tol = tolerancias || {}
  let c = corpoJsonRhid(corpo)
  if (typeof c === 'string') c = corpoJsonRhid(c)
  if (c && !Array.isArray(c) && typeof c === 'object') {
    if (Array.isArray(c.records)) c = c.records
    else throw new Error(`RHiD apuração: ${String(c.error || c.message || 'resposta inesperada').slice(0, 200)}`)
  }
  if (!Array.isArray(c)) throw new Error('RHiD apuração: resposta sem lista de dias')
  const dias = []
  for (const d of c) {
    if (!d || typeof d !== 'object') continue
    const data = String(d.date || d.dateTimeStr || '').replace(/^(\d{4})(\d{2})(\d{2})$/, '$1-$2-$3').slice(0, 10)
    if (!dataValidaRhid(data)) continue
    const horarios = String(d.strHorarioContratualSimples || '')
      .split(/[\r\n]+/)
      .flatMap((faixa) => faixa.split('-').map((h) => h.trim()))
      .filter((h) => /^\d{1,2}:\d{2}$/.test(h))
    let feriado = null
    if (Number(d.isHoliday) > 0 || d.holiday) {
      let h = d.holiday
      if (typeof h === 'string') h = corpoJsonRhid(h)
      feriado = String((h && typeof h === 'object' && h.name) || 'Feriado').slice(0, 120)
    }
    const folga = d.folga === true
    const uteis = Math.max(0, Math.min(1440, Math.trunc(Number(d.horasUteis) || 0)))
    // sem horário no RHiD (pessoa sem escala/horário): o RHiD não apura → apaga o previsto (vale a jornada/escala daqui)
    if (!horarios.length && !uteis && !folga && !feriado) { dias.push({ cpf, data, sem_horario: true }); continue }
    dias.push({
      cpf,
      data,
      previsto_minutos: folga || feriado ? 0 : uteis,
      horarios,
      folga,
      feriado,
      saldo_minutos: Number.isFinite(Number(d.saldoBancoCredDeb)) ? Math.trunc(Number(d.saldoBancoCredDeb)) : null,
      tolerancia_extra_minutos: tol.extra || 0,
      tolerancia_falta_minutos: tol.falta || 0,
    })
  }
  return dias
}

/** Tolerância diária de um horário do RHiD (ShiftDTO.tolerancias): lim_min_diario_horas_extras / _faltas; CLT = 10. */
export function toleranciasTurnoRhid(turno) {
  const lista = Array.isArray(turno && turno.tolerancias) ? turno.tolerancias : []
  const valor = (codigo) => { const t = lista.find((x) => x && x.code === codigo); return t ? t.value : undefined }
  const clt = valor('tolerancia_clt') === true
  const num = (v) => (Number.isFinite(Number(v)) && v !== null && v !== '' && typeof v !== 'boolean' ? Math.max(0, Math.min(120, Math.trunc(Number(v)))) : null)
  return {
    extra: num(valor('lim_min_diario_horas_extras')) ?? (clt ? 10 : 0),
    falta: num(valor('lim_min_diario_faltas')) ?? (clt ? 10 : 0),
  }
}

/**
 * Horários previstos: para cada CPF ligado a funcionário (ingestao_rhid_vinculados), pede a apuração do RHiD no período
 * e grava em lotes (ingestao_rhid_horarios, que reapura os dias alterados). Pessoa com erro vira aviso.
 * deps: { rpc, tamanhoLote? }
 */
export async function importarHorariosRhid(config, entrada, sessao, deps) {
  const janela = janelaHorariosRhid(entrada, config)
  const avisos = []
  const falhas = []
  const vinculados = ((await deps.rpc('ingestao_rhid_vinculados', { p_integracao: config.integracao_id })) || []).map(cpfRhid).filter(Boolean)
  if (!sessao.pessoas) sessao.pessoas = await sessao.listar('/person', 'pessoas')
  const idPorCpf = new Map()
  const turnoPorCpf = new Map()
  for (const x of sessao.pessoas) {
    const c = cpfRhid(x && x.cpf)
    if (c && Number(x.id) > 0 && !idPorCpf.has(c)) { idPorCpf.set(c, Number(x.id)); turnoPorCpf.set(c, Number(x.idShift) > 0 ? Number(x.idShift) : null) }
  }
  const turnos = new Map()
  const toleranciaDo = async (idTurno) => {
    if (!idTurno) return { extra: 0, falta: 0 }
    if (!turnos.has(idTurno)) {
      try {
        const corpo = await sessao.chamar((token) => ({ method: 'GET', url: urlRhid(sessao.base, `/shift/${idTurno}`, {}), headers: cabecalhosRhid(token), timeoutMs: deps.timeoutMs || 120000 }), `RHiD horário ${idTurno}`)
        turnos.set(idTurno, toleranciasTurnoRhid(corpoJsonRhid(corpo)))
      } catch (e) {
        avisos.push(`horário ${idTurno}: tolerância não lida (${String(e && e.message ? e.message : e).slice(0, 80)})`)
        turnos.set(idTurno, { extra: 0, falta: 0 })
      }
    }
    return turnos.get(idTurno)
  }
  let dias = []
  let pessoas = 0
  for (const cpf of vinculados) {
    const id = idPorCpf.get(cpf)
    if (!id) { avisos.push(`CPF …${cpf.slice(-2)} ligado, mas não está nas pessoas do RHiD`); continue }
    try {
      const corpo = await sessao.chamar((token) => ({ method: 'GET', url: urlRhid(sessao.base, '/apuracao_ponto', { idPerson: id, dataIni: janela.dataIni, dataFinal: janela.dataFinal }), headers: cabecalhosRhid(token), timeoutMs: deps.timeoutMs || 120000 }), `RHiD apuração ${id}`)
      const turno = turnoPorCpf.get(cpf)
      const doDia = diasApuracaoRhid(corpo, cpf, await toleranciaDo(turno))
      // sem horário (turno) no RHiD: nenhum dia vale, nem feriado — o RHiD não apura essa pessoa
      dias = dias.concat(turno ? doDia : doDia.map((x) => ({ cpf, data: x.data, sem_horario: true })))
      pessoas++
    } catch (e) {
      falhas.push(`pessoa ${id}: ${e && e.message ? e.message : String(e)}`.slice(0, 200))
    }
  }
  if (vinculados.length && !pessoas && falhas.length) {
    const e = new Error(falhas.slice(0, 3).join(' | '))
    e.tentativas = sessao.tentativasMax
    throw e
  }
  const tot = { gravados: 0, apagados: 0, iguais: 0, ignorados: 0, reapurados: 0 }
  for (const lote of lotesRhid(dias, deps.tamanhoLote || 2000)) {
    const r = (await deps.rpc('ingestao_rhid_horarios', { p_integracao: config.integracao_id, p_dias: lote })) || {}
    tot.gravados += Number(r.gravados) || 0
    tot.apagados += Number(r.apagados) || 0
    tot.iguais += Number(r.iguais) || 0
    tot.ignorados += Number(r.ignorados) || 0
    tot.reapurados += Number(r.funcionarios_reapurados) || 0
  }
  return {
    status: falhas.length ? 'parcial' : 'sucesso',
    lidos: dias.length,
    gravados: tot.gravados,
    ignorados: tot.ignorados,
    erro: falhas.length ? `${falhas.length} pessoa(s) sem apuração: ${falhas.slice(0, 2).join(' | ')}` : null,
    detalhes: { janela, vinculados: vinculados.length, pessoas, iguais: tot.iguais, apagados: tot.apagados, sem_horario: dias.filter((x) => x.sem_horario).length, funcionarios_reapurados: tot.reapurados, avisos: avisos.slice(0, 20), logins: sessao.logins },
    tentativas: sessao.tentativasMax,
  }
}

/** Junta as saídas de `comExecucao` (pessoas, batidas) na saída do subfluxo (§12.3): pior status, somas, todos os ids. */
export function juntarSaidasRhid(saidas) {
  const lista = (saidas || []).filter(Boolean)
  if (!lista.length) return { execucao_ids: [], status: 'erro', lidos: 0, gravados: 0, ignorados: 0, erro: 'Nada a fazer para este escopo' }
  const ordem = { sucesso: 0, parcial: 1, erro: 2 }
  const pior = lista.reduce((a, s) => (ordem[s.status] > ordem[a] ? s.status : a), 'sucesso')
  const erros = lista.map((s) => s.erro).filter(Boolean)
  return {
    execucao_ids: lista.flatMap((s) => s.execucao_ids || []),
    status: pior,
    lidos: lista.reduce((a, s) => a + (Number(s.lidos) || 0), 0),
    gravados: lista.reduce((a, s) => a + (Number(s.gravados) || 0), 0),
    ignorados: lista.reduce((a, s) => a + (Number(s.ignorados) || 0), 0),
    erro: erros.length ? erros.join(' | ').slice(0, 1000) : null,
  }
}
