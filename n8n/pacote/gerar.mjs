#!/usr/bin/env node
// Pacote de implantação do N8N (ver docs/IMPLANTACAO-N8N-HOSTINGER.md): copia os workflows na ORDEM de importação para
// n8n/pacote/workflows/NN-<nome>.json e gera n8n/pacote/env.hostinger.exemplo (sem segredos). Sem dependências, sem zip:
// baixe a pasta n8n/pacote/ inteira (ou só workflows/) e importe os arquivos 01 → 10 no N8N.
//
// Uso:  node n8n/pacote/gerar.mjs            (regenera)
//       node n8n/pacote/gerar.mjs --conferir (só confere; sai com 1 se estiver desatualizado — também roda em `npm run n8n:verificar`)

import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync, rmSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const PACOTE = dirname(fileURLToPath(import.meta.url))
const N8N = join(PACOTE, '..')
const SAIDA = join(PACOTE, 'workflows')

/** Ordem de importação: primeiro o tratador de erros, depois os subfluxos, por último os que têm agenda (ativar 08 → 09 → 10). */
export const ORDEM_IMPORTACAO = [
  { arquivo: 'comum/workflows/erros.json', variavel: null, ativar: false },
  { arquivo: 'controlid/workflows/controlid-importar-usuarios.json', variavel: 'MDG_WF_CONTROLID_USUARIOS', ativar: false },
  { arquivo: 'controlid/workflows/controlid-importar-batidas.json', variavel: 'MDG_WF_CONTROLID_BATIDAS', ativar: false },
  { arquivo: 'controlid/workflows/controlid-exportar-usuarios.json', variavel: 'MDG_WF_CONTROLID_EXPORTAR', ativar: false },
  { arquivo: 'zig/workflows/zig-importar.json', variavel: 'MDG_WF_ZIG_IMPORTAR', ativar: false },
  { arquivo: 'tagme/workflows/tagme-importar.json', variavel: 'MDG_WF_TAGME_IMPORTAR', ativar: false },
  { arquivo: 'comum/workflows/exportar-fechamento.json', variavel: 'MDG_WF_EXPORTAR_FECHAMENTO', ativar: false },
  { arquivo: 'comum/workflows/sincronizar-agora.json', variavel: null, ativar: true },
  { arquivo: 'comum/workflows/agendador.json', variavel: null, ativar: true },
  { arquivo: 'comum/workflows/rotina-diaria.json', variavel: null, ativar: true },
]

const base = (arq) => arq.split('/').pop()
export const nomeNoPacote = (i, arq) => `${String(i + 1).padStart(2, '0')}-${base(arq)}`

const VARS_WF = ORDEM_IMPORTACAO.filter((o) => o.variavel)

export function envHostinger() {
  const linhas = VARS_WF.map((o) => {
    const i = ORDEM_IMPORTACAO.indexOf(o)
    return `${o.variavel}=            # id do workflow ${nomeNoPacote(i, o.arquivo)}`
  })
  return `# Variáveis do N8N do Meu Dia de Gerente — modelo para a VPS Hostinger (docs/IMPLANTACAO-N8N-HOSTINGER.md §3).
# Gerado por n8n/pacote/gerar.mjs. SEM SEGREDOS: preencha na VPS (no .env ao lado do docker-compose.yml), nunca no repositório.
# Linhas deste bloco vão para o .env do Docker Compose E precisam ser repassadas ao container (seção "environment:" ou "env_file:").

# --- Supabase (Project Settings → API) -----------------------------------------------------------------------------------
SUPABASE_URL=https://SEU-PROJETO.supabase.co
SUPABASE_SERVICE_ROLE_KEY=cole-aqui-a-service-role-key

# --- ids dos subfluxos (preencha DEPOIS de importar; o id está na URL: .../workflow/<id>) ---------------------------------
${linhas.join('\n')}

# --- comportamento do N8N ------------------------------------------------------------------------------------------------
N8N_BLOCK_ENV_ACCESS_IN_NODE=false
GENERIC_TIMEZONE=America/Sao_Paulo
TZ=America/Sao_Paulo
N8N_RUNNERS_TASK_TIMEOUT=900
EXECUTIONS_TIMEOUT=-1

# --- integrações e e-mail ------------------------------------------------------------------------------------------------
ZIG_BASE_URL=https://api.zigcore.com.br/integration
# URL base da Tagme usada quando a integração não tiver parametros.base_url (exemplo: o domínio do painel; o CAMINHO do
# endpoint de reservas é configurado na tela Integrações → Tagme). Pode ficar vazio.
TAGME_BASE_URL=
MDG_EMAIL_RELATORIOS=
MDG_EMAIL_REMETENTE=
`
}

export function leiaMe() {
  const linhas = ORDEM_IMPORTACAO.map((o, i) => {
    const wf = JSON.parse(readFileSync(join(N8N, o.arquivo), 'utf8'))
    return `${nomeNoPacote(i, o.arquivo).padEnd(40)} ${wf.name.padEnd(44)} ${o.variavel ? `→ ${o.variavel}` : o.ativar ? '→ ATIVAR' : ''}`.trimEnd()
  })
  return `PACOTE DE IMPLANTAÇÃO DO N8N — Meu Dia de Gerente
Passo a passo completo: docs/IMPLANTACAO-N8N-HOSTINGER.md

1. Importe os arquivos de workflows/ NESTA ORDEM (N8N → Workflows → Import from File):

${linhas.join('\n')}

2. Anote o id de cada subfluxo (na URL: .../workflow/<id>) e preencha a variável indicada em env.hostinger.exemplo.
3. Reinicie o N8N (docker compose up -d), aponte o Error workflow, configure o SMTP e ative 08 → 09 → 10.

Gerado por n8n/pacote/gerar.mjs — não edite à mão (as cópias são conferidas por npm run n8n:verificar).
`
}

/** Conteúdo esperado de cada arquivo do pacote: { caminhoRelativoAoPacote: texto }. */
export function arquivosEsperados() {
  const saida = {}
  ORDEM_IMPORTACAO.forEach((o, i) => { saida[`workflows/${nomeNoPacote(i, o.arquivo)}`] = readFileSync(join(N8N, o.arquivo), 'utf8') })
  saida['env.hostinger.exemplo'] = envHostinger()
  saida['LEIA-ME.txt'] = leiaMe()
  return saida
}

/** Regrava o pacote. Retorna os arquivos alterados. */
export function gerarPacote() {
  const esperado = arquivosEsperados()
  mkdirSync(SAIDA, { recursive: true })
  for (const f of readdirSync(SAIDA)) if (!esperado[`workflows/${f}`]) rmSync(join(SAIDA, f))
  const alterados = []
  for (const [rel, conteudo] of Object.entries(esperado)) {
    const p = join(PACOTE, rel)
    if (existsSync(p) && readFileSync(p, 'utf8') === conteudo) continue
    writeFileSync(p, conteudo)
    alterados.push(rel)
  }
  return alterados
}

/** Lista de problemas (vazia = pacote em dia). */
export function conferirPacote() {
  const problemas = []
  const esperado = arquivosEsperados()
  for (const [rel, conteudo] of Object.entries(esperado)) {
    const p = join(PACOTE, rel)
    if (!existsSync(p)) problemas.push(`${rel} não existe — rode \`node n8n/pacote/gerar.mjs\``)
    else if (readFileSync(p, 'utf8') !== conteudo) problemas.push(`${rel} desatualizado em relação ao original — rode \`node n8n/pacote/gerar.mjs\``)
  }
  if (existsSync(SAIDA)) for (const f of readdirSync(SAIDA)) if (!esperado[`workflows/${f}`]) problemas.push(`workflows/${f} sobrando no pacote`)
  // todo subfluxo despachado tem variável no pacote; nenhum segredo no modelo de .env
  const env = esperado['env.hostinger.exemplo']
  const sup = readFileSync(join(N8N, 'comum/lib/supabase.mjs'), 'utf8')
  for (const v of sup.matchAll(/'(MDG_WF_[A-Z_]+)'/g)) if (!env.includes(`${v[1]}=`)) problemas.push(`env.hostinger.exemplo sem ${v[1]}`)
  if (/eyJ[A-Za-z0-9_-]{8,}\.|sb_secret_|token-mock/.test(env)) problemas.push('env.hostinger.exemplo com segredo')
  return problemas
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  if (process.argv.includes('--conferir')) {
    const p = conferirPacote()
    for (const x of p) console.log(`ERRO   pacote: ${x}`)
    console.log(p.length ? `${p.length} problema(s).` : 'Pacote em dia.')
    process.exit(p.length ? 1 : 0)
  }
  const alterados = gerarPacote()
  console.log(alterados.length ? `Pacote atualizado: ${alterados.join(', ')}` : 'Pacote já estava em dia.')
}
