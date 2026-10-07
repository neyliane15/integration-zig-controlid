// CSV no formato único do contrato §13 — réplica de web/src/lib/csv.ts (mesma saída byte a byte).
// Funções puras, sem import. Copiada nos nós Code com `// @lib comum/lib/csv.mjs` (conferida por `npm run n8n:verificar`).
//
// - UTF-8 com BOM, separador `;`, TODA linha termina em `\r\n` (inclusive a última).
// - Aspas duplas quando o campo tem `;`, `"`, `\r` ou `\n` (aspas internas dobradas).
// - `null`/`undefined` → vazio; `true`/`false` → `Sim`/`Não`; números como `String(n)`.
// - `preambulo` (opcional): linhas antes do cabeçalho, seguidas automaticamente de uma linha em branco.
// - (revisão 2) Injeção de fórmula: texto que começa com `=`, `+`, `-`, `@`, TAB ou CR (ex.: nome de garçom vindo da Zig,
//   nome de funcionário) ganha um apóstrofo na frente (`'=HYPERLINK(…)`) para o Excel/LibreOffice não executar como fórmula.
//   Números que NÓS geramos (`-50,00`, `-03:26`, `-1`) continuam como estão.

export const CSV_BOM = '﻿'
export const CSV_FIM = '\r\n'

const CSV_FORMULA = /^[=+\-@\t\r]/
const CSV_NUMERO = /^[-+]?\d+(?:[.,:]\d+)*$/

export function campoCsv(v) {
  if (v === null || v === undefined) return ''
  let texto = typeof v === 'boolean' ? (v ? 'Sim' : 'Não') : String(v)
  if (CSV_FORMULA.test(texto) && !CSV_NUMERO.test(texto)) texto = `'${texto}`
  return /[;"\r\n]/.test(texto) ? `"${texto.replace(/"/g, '""')}"` : texto
}

export function linhaCsv(valores) {
  return valores.map(campoCsv).join(';') + CSV_FIM
}

export function gerarCsv(cabecalho, linhas, preambulo) {
  let saida = CSV_BOM
  if (preambulo && preambulo.length > 0) {
    for (const l of preambulo) saida += linhaCsv(l)
    saida += CSV_FIM
  }
  saida += linhaCsv(cabecalho)
  for (const l of linhas) saida += linhaCsv(l)
  return saida
}

/** 209474 → "2094,74"; -5000 → "-50,00"; null → "". */
export function centavosCsv(c) {
  if (c === null || c === undefined || c === '') return ''
  const n = Number(c)
  const negativo = n < 0
  const abs = Math.abs(Math.trunc(n))
  return `${negativo ? '-' : ''}${Math.floor(abs / 100)},${String(abs % 100).padStart(2, '0')}`
}

/** -206 → "-03:26"; null → "". */
export function minutosCsv(m) {
  if (m === null || m === undefined || m === '') return ''
  const n = Number(m)
  const abs = Math.abs(Math.trunc(n))
  return `${n < 0 ? '-' : ''}${String(Math.floor(abs / 60)).padStart(2, '0')}:${String(abs % 60).padStart(2, '0')}`
}

/** "2026-10-06" → "06/10/2026"; null → "". */
export function dataCsv(iso) {
  if (!iso) return ''
  const [a = '', m = '', d = ''] = String(iso).slice(0, 10).split('-')
  return `${d}/${m}/${a}`
}

/** Número decimal (pontos, percentuais) com vírgula e sem zeros à direita: 10 → "10"; 2.5 → "2,5"; 7.333333 → "7,333333". */
export function numeroCsv(v, casas) {
  if (v === null || v === undefined || v === '') return ''
  const n = Number(v)
  if (!Number.isFinite(n)) return ''
  const fixo = n.toFixed(casas ?? 6)
  return fixo.replace(/\.?0+$/, '').replace('.', ',').replace(/^-0$/, '0')
}

/** "Bar Bossa Nova" → "bar-bossa-nova" (nome de arquivo, §13). */
export function slug(s) {
  return (
    String(s || '')
      .normalize('NFD')
      .replace(/\p{Diacritic}/gu, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '') || 'empresa'
  )
}

/** `<tipo>_<empresa-slug>_<aaaa-mm-dd>[_<aaaa-mm-dd>].csv` (§13). */
export function nomeArquivoCsv(tipo, empresa, inicio, fim) {
  return `${tipo}_${slug(empresa)}_${inicio}${fim && fim !== inicio ? `_${fim}` : ''}.csv`
}

export const COLUNAS_COMISSAO = ['Funcionário', 'Cargo', 'Incluído', 'Pontos', 'Dias trabalhados', 'Pontos efetivos', 'Valor (R$)']

const ROTULO_STATUS_FECHAMENTO = { rascunho: 'Rascunho', fechado: 'Fechado' }

/**
 * CSV do fechamento de comissão (§13) a partir do retorno de `ingestao_fechamento_exportar`:
 * `{ fechamento: {...colunas de comissao_fechamentos, empresa_nome}, itens: [{...colunas de comissao_itens}] }`.
 * Retorna `{ nome, conteudo, linhas }`.
 *  - preâmbulo: Período; Serviço Zig (R$); Ajuste (R$); Serviço bruto (R$); Retenção (%); Retenção (R$);
 *    Base distribuível (R$); Valor do ponto (R$) (centavos arredondados); Status — e uma linha em branco;
 *  - itens na ordem recebida (o banco ordena por nome); `Incluído` Sim/Não;
 *  - linha final `Total;;;<Σ pontos dos incluídos>;;<Σ pontos efetivos>;<base distribuível>`.
 */
export function csvComissao(dados) {
  const f = (dados && dados.fechamento) || {}
  const itens = Array.isArray(dados && dados.itens) ? dados.itens : []
  if (!f.data_inicio || !f.data_fim) throw new Error('Fechamento sem período')
  const valorPonto = f.valor_ponto_centavos === null || f.valor_ponto_centavos === undefined ? null : Math.round(Number(f.valor_ponto_centavos))
  const preambulo = [
    ['Período', `${dataCsv(f.data_inicio)} a ${dataCsv(f.data_fim)}`],
    ['Serviço Zig (R$)', centavosCsv(f.servico_zig_centavos ?? 0)],
    ['Ajuste (R$)', centavosCsv(f.servico_ajuste_centavos ?? 0)],
    ['Serviço bruto (R$)', centavosCsv(f.servico_bruto_centavos ?? 0)],
    ['Retenção (%)', numeroCsv(f.percentual_retencao ?? 0, 2)],
    ['Retenção (R$)', centavosCsv(f.retencao_centavos ?? 0)],
    ['Base distribuível (R$)', centavosCsv(f.base_distribuivel_centavos ?? 0)],
    ['Valor do ponto (R$)', centavosCsv(valorPonto)],
    ['Status', ROTULO_STATUS_FECHAMENTO[f.status] || f.status || ''],
  ]
  let somaPontos = 0
  let somaPe = 0
  const linhas = itens.map((i) => {
    const incluido = i.incluido !== false
    if (incluido) somaPontos += Number(i.pontos) || 0
    somaPe += Number(i.pontos_efetivos) || 0
    return [
      i.funcionario_nome ?? '',
      i.cargo ?? '',
      incluido,
      numeroCsv(i.pontos, 2),
      i.dias_trabalhados ?? 0,
      numeroCsv(i.pontos_efetivos, 6),
      centavosCsv(i.valor_centavos ?? 0),
    ]
  })
  linhas.push(['Total', '', '', numeroCsv(somaPontos, 2), '', numeroCsv(somaPe, 6), centavosCsv(f.base_distribuivel_centavos ?? 0)])
  return {
    nome: nomeArquivoCsv('comissao', f.empresa_nome || 'empresa', f.data_inicio, f.data_fim),
    conteudo: gerarCsv(COLUNAS_COMISSAO, linhas, preambulo),
    linhas: itens.length,
  }
}
